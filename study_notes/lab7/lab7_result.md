# 前言

lab7涉及到的是进程间的通信,如何做好同步互斥,这里主要用到两个方法,一个是信号量,一个是管程,然后管程也是基于信号量来实现的,接下来我们来看下具体的实现吧(个人感觉lab7还是比较难的,需要清晰地弄清楚同步互斥的各种概念).

# 正文

## Part0

需要改的文件包括：

- default_pmm.c
- default_sched.c
- kdebug.c
- pmm.c
- proc.c
- swap_fifo.c
- trap.c
- vmm.c

其中trap.c需要修改一下

```c
ticks ++;
assert(current != NULL);
run_timer_list();
```

因为在lab7中我们引入了进程sleep，所以需要引入计时器timer，调度器每次更新time相关信息，如果过期，那么就唤醒进程．

## 练习1: 理解内核级信号量的实现和基于内核级信号量的哲学家就餐问题（不需要编码）

我们首先来分析下利用信号量实现的哲学家问题，我们先看下信号量的结构．

```c
typedef struct {
    int value;
    wait_queue_t wait_queue;
} semaphore_t;
```

信号量中包含value用于计数，和一个等待队列wait_queue用来维护挂在这个信号量上的进程，然后我们稍微看下等待队列

```c
typedef struct {
    list_entry_t wait_head;
} wait_queue_t;
```

就是一个简单的双向链表结构，然后里面会有一些相应的操作，这里我准备放在后面分析．（其中底层实现还有计时器和一个硬件支持的中断屏蔽都暂且放在后面）

然后看下信号量中的几个操作

```c
void
sem_init(semaphore_t *sem, int value) {
    sem->value = value;
    wait_queue_init(&(sem->wait_queue));
}
```

初始化信号量的值和等待队列．

然后是up,先是local_intr_save和local_intr_restore两个硬件支持的屏蔽中断和使能中断来操作寄存器的eflag位，来保证我们的操作是原子的，如果等待队列中不存在进程的话，直接value+1就行了，否则拿到等待队列中的进程后assert一下原来是不是wait_state状态，然后唤醒等待队列中的第一个队列，最后取消屏蔽

```c
static __noinline void __up(semaphore_t *sem, uint32_t wait_state) {
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        wait_t *wait;
        if ((wait = wait_queue_first(&(sem->wait_queue))) == NULL) {
            sem->value ++;
        }
        else {
            assert(wait->proc->wait_state == wait_state);
            wakeup_wait(&(sem->wait_queue), wait, wait_state, 1);
        }
    }
    local_intr_restore(intr_flag);
}
```

然后看下down,首先判断信号量value是不是大于0，直接--然后返回就行了，否则的话需要将当前进程加入等待队列中，然后调用schedule，选择另一个进程继续执行，当这个进程被唤醒后然后从等待队列中删除（注意屏蔽中断）

```c
static __noinline uint32_t __down(semaphore_t *sem, uint32_t wait_state) {
    bool intr_flag;
    local_intr_save(intr_flag);
    if (sem->value > 0) {
        sem->value --;
        local_intr_restore(intr_flag);
        return 0;
    }
    wait_t __wait, *wait = &__wait;
    wait_current_set(&(sem->wait_queue), wait, wait_state);
    local_intr_restore(intr_flag);

    schedule();

    local_intr_save(intr_flag);
    wait_current_del(&(sem->wait_queue), wait);
    local_intr_restore(intr_flag);

    if (wait->wakeup_flags != wait_state) {
        return wait->wakeup_flags;
    }
    return 0;
}
```

到这里准备工作差不多了，我们来看下具体流程，同样是从init.c中追踪，proc_init()函数，init_main()函数，然后这里有修改的地方

```c
extern void check_sync(void);
check_sync();                // check philosopher sync problem
```

调用check_sync函数，有两部分分别是用信号量和管程实现的哲学家问题．

```c
void check_sync(void){

    int i;

    //check semaphore
    sem_init(&mutex, 1);
    for(i=0;i<N;i++){
        sem_init(&s[i], 0);
        int pid = kernel_thread(philosopher_using_semaphore, (void *)i, 0);
        if (pid <= 0) {
            panic("create No.%d philosopher_using_semaphore failed.\n");
        }
        philosopher_proc_sema[i] = find_proc(pid);
        set_proc_name(philosopher_proc_sema[i], "philosopher_sema_proc");
    }

    //check condition variable
    monitor_init(&mt, N);
    for(i=0;i<N;i++){
        state_condvar[i]=THINKING;
        int pid = kernel_thread(philosopher_using_condvar, (void *)i, 0);
        if (pid <= 0) {
            panic("create No.%d philosopher_using_condvar failed.\n");
        }
        philosopher_proc_condvar[i] = find_proc(pid);
        set_proc_name(philosopher_proc_condvar[i], "philosopher_condvar_proc");
    }
}
```

看一下先初始化一个mutex锁（同样是用信号量实现的），然后s是一个用于存放哲学家的信号量数组，我们循环5个哲学家线程出来，然后我们跟进下philosopher_using_condvar函数．

来分析下哲学家的具体操作，首先是睡一下作为思考，然后phi_take_forks_sema()来获取叉子，do_sleep一段时间表示吃饭，然后phi_put_forks_sema放下叉子

```c
int philosopher_using_semaphore(void * arg) /* i：哲学家号码，从0到N-1 */
{
    int i, iter=0;
    i=(int)arg;
    cprintf("I am No.%d philosopher_sema\n",i);
    while(iter++<TIMES)
    { /* 无限循环 */
        cprintf("Iter %d, No.%d philosopher_sema is thinking\n",iter,i); /* 哲学家正在思考 */
        do_sleep(SLEEP_TIME);
        phi_take_forks_sema(i); 
        /* 需要两只叉子，或者阻塞 */
        cprintf("Iter %d, No.%d philosopher_sema is eating\n",iter,i); /* 进餐 */
        do_sleep(SLEEP_TIME);
        phi_put_forks_sema(i); 
        /* 把两把叉子同时放回桌子 */
    }
    cprintf("No.%d philosopher_sema quit\n",i);
    return 0;    
}
```

跟进下，mutex信号量实现的锁，down,up来维护一个临界区，然后自己转为饥饿状态HUNGRY，然后phi_test_sema()具体视图获取叉子，离开临界区后我们需要down一下自己，如果没拿到叉子就会阻塞自己，否则就减下信号量的值

```c
void phi_take_forks_sema(int i) /* i：哲学家号码从0到N-1 */
{ 
        down(&mutex); /* 进入临界区 */
        state_sema[i]=HUNGRY; /* 记录下哲学家i饥饿的事实 */
        phi_test_sema(i); /* 试图得到两只叉子 */
        up(&mutex); /* 离开临界区 */
        down(&s[i]); /* 如果得不到叉子就阻塞 */
}
```

来看下phi_test_sema这个函数，如果自己是饥饿的并且，左手和右手都不在吃，那么自己转换吃EATING状态，然后up一下自己这个信号量．

```c
void phi_test_sema(i) /* i：哲学家号码从0到N-1 */
{ 
    if(state_sema[i]==HUNGRY&&state_sema[LEFT]!=EATING
            &&state_sema[RIGHT]!=EATING)
    {
        state_sema[i]=EATING;
        up(&s[i]);
    }
}
```

再看下phi_put_forks_sema，临界区保护下后，装换为思考状态，然后test左右哲学家

```c
void phi_put_forks_sema(int i) /* i：哲学家号码从0到N-1 */
{ 
        down(&mutex); /* 进入临界区 */
        state_sema[i]=THINKING; /* 哲学家进餐结束 */
        phi_test_sema(LEFT); /* 看一下左邻居现在是否能进餐 */
        phi_test_sema(RIGHT); /* 看一下右邻居现在是否能进餐 */
        up(&mutex); /* 离开临界区 */
}
```

总结下哲学家就是在五个线程里面不断的从思考－饥饿－进餐三个状态不断转换，然后进行状态转换是需要用mutex加锁来保护变量，然后注意在哲学家进餐的时候需要利用信号量加锁防止重入，注意每个down,up操作都是一一对应的．

## Part2 完成内核级条件变量和基于内核级条件变量的哲学家就餐问题（需要编码）

同样先看下管程的结构

```c
typedef struct monitor{
    semaphore_t mutex;      // the mutex lock for going into the routines in monitor, should be initialized to 1
    semaphore_t next;       // the next semaphore is used to down the signaling proc itself, and the other OR wakeuped waiting proc should wake up the sleeped signaling proc.
    int next_count;         // the number of of sleeped signaling proc
    condvar_t *cv;          // the condvars in monitor
} monitor_t;
```

monitor管程，mutex信号量实现的锁，next和next_count是用做唤醒休眠时勇的，然后cv是一个条件变量，来看下这个数据结构

```c
typedef struct condvar{
    semaphore_t sem;        // the sem semaphore  is used to down the waiting proc, and the signaling proc should up the waiting proc
    int count;              // the number of waiters on condvar
    monitor_t * owner;      // the owner(monitor) of this condvar
} condvar_t;
```

有个信号量来维护，count来记录挂载这个条件变量的数目，然后owner表明这个条件变量属于哪个管程．然后我们来看下对条件变量的几个操作

先是管程的初始化，包括几个变量的赋初值，给条件变量malloc空间等

```c
// Initialize monitor.
void     
monitor_init (monitor_t * mtp, size_t num_cv) {
    int i;
    assert(num_cv>0);
    mtp->next_count = 0;
    mtp->cv = NULL;
    sem_init(&(mtp->mutex), 1); //unlocked
    sem_init(&(mtp->next), 0);
    mtp->cv =(condvar_t *) kmalloc(sizeof(condvar_t)*num_cv);
    assert(mtp->cv!=NULL);
    for(i=0; i<num_cv; i++){
        mtp->cv[i].count=0;
        sem_init(&(mtp->cv[i].sem),0);
        mtp->cv[i].owner=mtp;
    }
}
```

然后看下唤醒操作，假设现在的进程是B,如果count<=0说明没有睡在这个条件变量上的进程，否则就应该唤醒一个睡在sem这个信号量上的进程A,然后因为管程中只允许存在一个进程,所以当前进程B需要睡眠，所以next_count++，然后唤醒进程A,然后把自己睡在next上面，然后当其他进程返回后需要next_count--掉

```c
// Unlock one of threads waiting on the condition variable. 
void 
cond_signal (condvar_t *cvp) {
   //LAB7 EXERCISE1: YOUR CODE
   cprintf("cond_signal begin: cvp %x, cvp->count %d, cvp->owner->next_count %d\n", cvp, cvp->count, cvp->owner->next_count);  
  /*
   *      cond_signal(cv) {
   *          if(cv.count>0) {
   *             mt.next_count ++;
   *             signal(cv.sem);
   *             wait(mt.next);
   *             mt.next_count--;
   *          }
   *       }
   */
    if(cvp->count>0) {
        cvp->owner->next_count ++;
        up(&(cvp->sem));
        down(&(cvp->owner->next));
        cvp->owner->next_count --;
    }
   cprintf("cond_signal end: cvp %x, cvp->count %d, cvp->owner->next_count %d\n", cvp, cvp->count, cvp->owner->next_count);
}
```

再看下cond_wait函数，进程A因为条件变量不满足导致让自己睡过去，首先count++，然后需要分两个情况，

第一种情况当，next_count>0的时候，说明存在进程执行了cond_signal导致睡在next上，形成了一个进程链，那么就up唤醒其中的一个进程，然后把自己睡在sem信号量上，直到从别的进程中返回到这里再执行count--

第二种情况是next_count不存在，说明没有因为执行cond_signal而睡的进程，那么我们就需要唤醒因为互斥而无法进入的进程，然后当前进程睡在sem上，如果之后睡醒后，同样count--

```c
// Suspend calling thread on a condition variable waiting for condition Atomically unlocks 
// mutex and suspends calling thread on conditional variable after waking up locks mutex. Notice: mp is mutex semaphore for monitor's procedures
void
cond_wait (condvar_t *cvp) {
    //LAB7 EXERCISE1: YOUR CODE
    cprintf("cond_wait begin:  cvp %x, cvp->count %d, cvp->owner->next_count %d\n", cvp, cvp->count, cvp->owner->next_count);
   /*
    *         cv.count ++;
    *         if(mt.next_count>0)
    *            signal(mt.next)
    *         else
    *            signal(mt.mutex);
    *         wait(cv.sem);
    *         cv.count --;
    */
    cvp->count++;  // the number of need sleeping on this condition var proc + 1
    if(cvp->owner->next_count > 0)  // if next_count > 0, wake up next proc
        up(&(cvp->owner->next));
    else
        up(&(cvp->owner->mutex));  // else wake up sleeping on the mutex proc
    down(&(cvp->sem));  // wait itself
    cvp->count --;  // after other proc return then it wake up, the next_count - 1
    cprintf("cond_wait end:  cvp %x, cvp->count %d, cvp->owner->next_count %d\n", cvp, cvp->count, cvp->owner->next_count);
}
```

最后我们实现一下check_sync.c中的两个函数

首先是phi_take_forks_condvar，看一下显示把自己置为饥饿状态，然后尝试获取叉子phi_test_condvar(i)

```c
void phi_take_forks_condvar(int i) {
     down(&(mtp->mutex));
//--------into routine in monitor--------------
    // LAB7 EXERCISE1: YOUR CODE
    // I am hungry
    // try to get fork
    // I am hungry
    state_condvar[i]=HUNGRY;
    // try to get fork
    phi_test_condvar(i);
    if (state_condvar[i] != EATING) {
        cprintf("phi_take_forks_condvar: %d didn't get fork and will wait\n",i);
        cond_wait(&mtp->cv[i]);
    }
//--------leave routine in monitor--------------
      if(mtp->next_count>0)
         up(&(mtp->next));
      else
         up(&(mtp->mutex));
}
```

我们看下phi_test_condvar(i)，如果自己是饥饿并且左右没有在吃，那么把自己置换为EATING状态，然后这里利用条件变量尝试唤醒挂在当前sem的进程

```c
void phi_test_condvar (i) { 
    if(state_condvar[i]==HUNGRY&&state_condvar[LEFT]!=EATING
            &&state_condvar[RIGHT]!=EATING) {
        cprintf("phi_test_condvar: state_condvar[%d] will eating\n",i);
        state_condvar[i] = EATING ;
        cprintf("phi_test_condvar: signal self_cv[%d] \n",i);
        cond_signal(&mtp->cv[i]) ;
    }
}
```

接着上面的如果没有拿到叉子，说明条件没有满足，需要把自己wait掉让出管程，注意在最后我们都需要唤醒next或者mutex阻塞的进程．

然后看下phi_put_forks_condvar放叉子这个函数，将自己置为思考，然后去test左右的哲学家，此时可能就会唤醒因为没有得到条件变量而阻塞的哲学家，这个时候就会因为count>0的情况后，将next_count++然后up唤醒沉睡的进程，然后再把自己down在next形成一个进程队列，先等待那个被唤醒的进程完成工作返回后再继续执行．

```c
void phi_put_forks_condvar(int i) {
     down(&(mtp->mutex));

//--------into routine in monitor--------------
    // LAB7 EXERCISE1: YOUR CODE
    // I ate over
    // test left and right neighbors
    // I ate over
    state_condvar[i]=THINKING;
    // test left and right neighbors
    phi_test_condvar(LEFT);
    phi_test_condvar(RIGHT);
//--------leave routine in monitor--------------
     if(mtp->next_count>0)
        up(&(mtp->next));
     else
        up(&(mtp->mutex));
}
```

## 流程总结

这里拿两个哲学家的一次交互进行总结下，其实就是一个哲学家A拿到叉子后，down一下mutex这个信号量锁

```c
down(&(mtp->mutex));
```

，导致后来的哲学家B因为不满足条件变量，count++后，up mutex来做之后让出管程，同时这里把自己睡在sem上，当就餐完毕的哲学家A更改自己状态为THINKING后，test（假设是LEFT）尝试刚刚被阻塞的哲学家B，此时B所需要的条件变量满足了，然后进入cond_signal的函数，因为count>0，所以先把next_count++，然后up把B的sem信号量准备好，然后down把A睡在管程的next进程等待队列上,(注意，直到down函数调用schedule为止此时都一直是A进程在执行)，当schedule调度完成后，返回到down的位置，恢复A进程的phi_put_forks_condvar[LEFT]中调用的cond_signal中的next_count--，然后回到phi_put_forks_condvar函数，最后需要有一个

```c
if(mtp->next_count>0)
   up(&(mtp->next));
else
   up(&(mtp->mutex));
```

最后这个是保证因为cond_signal而睡眠的进程一定会被唤醒，比如其他进程进入管程最后都会在退出管程的时候确保next等待队列的进程都会被唤醒，所以每一个信号量的up和down都会有了一一对应的关系．

因此更多的哲学家都会类似上面的分析，只不过可能会多了几重的嵌套关系，不过在最后其都会被up down组合完成

## 底层支持

### 计时器

lab7需要do_sleep来实现定时器的作用，所以我们需要一个timer定时器的逻辑来完成，所以有了时间中断，

一个 timer_t 在系统中的存活周期可以被描述如下：

1. timer_t 在某个位置被创建和初始化，并通过 add_timer加入系统管理列表中
2. 系统时间被不断累加，直到 run_timer_list 发现该 timer_t到期。
3. run_timer_list更改对应的进程状态，并从系统管理列表中移除该timer_t。

主要是run_timer_list用来遍历timer链表来适时地唤醒相应的进程，大概看了下逻辑，没有什么特别难的地方，不过可以关注下add timer那里的操作比较精巧．

### 屏蔽与使能中断

```c
static inline bool
__intr_save(void) {
    if (read_eflags() & FL_IF) {
        intr_disable();
        return 1;
    }
    return 0;
}

static inline void
__intr_restore(bool flag) {
    if (flag) {
        intr_enable();
    }
}
```

```
关中断：local_intr_save --> __intr_save --> intr_disable --> cli
开中断：local_intr_restore--> __intr_restore --> intr_enable --> sti
```

主要就是cli和sti两个x86的指令，最终实现了关（屏蔽）中断和开（使能）中断，即设置了eflags寄存器中与中断相关的位。通过关闭中断，可以防止对当前执行的控制流被其他中断事件处理所打断。但是注意这里ucore只实现了的是单处理机下的情况，对于多处理机仅仅依靠屏蔽一个cpu的中断是不行的．

### 等待队列

当需要等待事件的进程在转入休眠状态后插入到等待队列中。当事件发生之后，内核遍历相应等待队列，唤醒休眠的用户进程或内核线程，并设置其状态为就绪状态（PROC_RUNNABLE），并将该进程从等待队列中清除。

```c
typedef  struct {
    struct proc_struct *proc;     //等待进程的指针
    uint32_t wakeup_flags;        //进程被放入等待队列的原因标记
    wait_queue_t *wait_queue;     //指向此wait结构所属于的wait_queue
    list_entry_t wait_link;       //用来组织wait_queue中wait节点的连接
} wait_t;

typedef struct {
    list_entry_t wait_head;       //wait_queue的队头
} wait_queue_t;

le2wait(le, member)               //实现wait_t中成员的指针向wait_t 指针的转化
```

以及一系列操作等待队列的函数这里就不再展开了．

# 总结

感觉这里同步互斥学的还不是特别好，之后感觉需要再返工学习下，尤其是管程这里比较难理解对于具体的代码，还需要细细地品，加油还有最后一个实验就做完了．