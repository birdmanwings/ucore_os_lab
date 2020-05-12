# 前言

五一佳节，宜学习。继续我们的lab6，lab6涉及到的是进程的调度，在lab5中进程调度只是简单的FIFO，而我们要在这里学习，实现调度器的部分(ps:咕到现在才传,有点累)。

# 正文

## Part0

同样是利用clion的compare功能，将lab1,2,3,4,5的内容填入到lab6中，然后我们还需要调整一部分代码来满足lab6。

主要填补的文件是:

- default_pmm.c
- kedebug.c
- pmm.c
- proc.c
- swap_fifo.c
- trap.c
- vmm.c

然后需要更改的几个文件

proc.c,添加了几个需要初始化的状态

```c
// alloc_proc - alloc a proc_struct and init all fields of proc_struct
static struct proc_struct *
alloc_proc(void) {
    struct proc_struct *proc = kmalloc(sizeof(struct proc_struct));
    if (proc != NULL) {
   	...
     //LAB6 YOUR CODE : (update LAB5 steps)
    /*
     * below fields(add in LAB6) in proc_struct need to be initialized
     *     struct run_queue *rq;                       // running queue contains Process
     *     list_entry_t run_link;                      // the entry linked in run queue
     *     int time_slice;                             // time slice for occupying the CPU
     *     skew_heap_entry_t lab6_run_pool;            // FOR LAB6 ONLY: the entry in the run pool
     *     uint32_t lab6_stride;                       // FOR LAB6 ONLY: the current stride of the process
     *     uint32_t lab6_priority;                     // FOR LAB6 ONLY: the priority of process, set by lab6_set_priority(uint32_t)
     */
        proc->state = PROC_UNINIT;
        proc->pid = -1;
        proc->runs = 0;
        proc->kstack = 0;
        proc->need_resched = 0; // needn't to schedule
        proc->parent = NULL;
        proc->mm = NULL;
        memset(&(proc->context), 0, sizeof(struct context));
        proc->tf = NULL;
        proc->cr3 = boot_cr3;  // boot_cr3 is pointed to page directory's physical location in pmm_init() function
        proc->flags = 0;
        memset(proc->name, 0, PROC_NAME_LEN);
        // from here is lab5
        proc->wait_state = 0;  // init process wait state
        proc->cptr = proc->optr = proc->yptr = NULL;  // init the pointers of processs
        // from here is lab6
        proc->rq = NULL; // init the running queue with NULL
        list_init(&(proc->run_link));  // init the entry linked pointer
        proc->time_slice = 0;  // init the time slice
        proc->lab6_run_pool.left = proc->lab6_run_pool.right = proc->lab6_run_pool.parent = NULL;  // init the different pointer
        proc->lab6_stride = 0;  // init the stride
        proc->lab6_priority = 0; // init the priority
    }
    return proc;
}
```

trap.c中的trap_dispatch函数,需要改变下使用时钟的函数

```c
// from here is lab6 code updated
ticks++;
assert(current!=NULL);
sched_class_proc_tick(current);
break;
```
## Part1 使用 Round Robin 调度算法（不需要编码）

我们需要看下整个进程调度的架构

```c
// The introduction of scheduling classes is borrrowed from Linux, and makes the 
// core scheduler quite extensible. These classes (the scheduler modules) encapsulate 
// the scheduling policies. 
struct sched_class {
    // the name of sched_class
    const char *name;
    // Init the run queue
    void (*init)(struct run_queue *rq);
    // put the proc into runqueue, and this function must be called with rq_lock
    void (*enqueue)(struct run_queue *rq, struct proc_struct *proc);
    // get the proc out runqueue, and this function must be called with rq_lock
    void (*dequeue)(struct run_queue *rq, struct proc_struct *proc);
    // choose the next runnable task
    struct proc_struct *(*pick_next)(struct run_queue *rq);
    // dealer of the time-tick
    void (*proc_tick)(struct run_queue *rq, struct proc_struct *proc);
    /* for SMP support in the future
     *  load_balance
     *     void (*load_balance)(struct rq* rq);
     *  get some proc from this rq, used in load_balance,
     *  return value is the num of gotten proc
     *  int (*get_proc)(struct rq* rq, struct proc* procs_moved[]);
     */
};
```

类似页面置换,我们同样拥有一个算法的框架调度器,让具体算法抽象出来,然后我们怎么维护进程呢,ucore里面维护了一个全局变量,一个双向链表来维护进程队列,

```c
struct run_queue {
    list_entry_t run_list;
    unsigned int proc_num;
    int max_time_slice;
    // For LAB6 ONLY
    skew_heap_entry_t *lab6_run_pool;
};
```

然后看一下proc.h中同样维护了一些信息

```c
struct proc_struct {
    ...
    struct run_queue *rq;                       // running queue contains Process
    list_entry_t run_link;                      // the entry linked in run queue
    int time_slice;                             // time slice for occupying the CPU
    skew_heap_entry_t lab6_run_pool;            // FOR LAB6 ONLY: the entry in the run pool
    uint32_t lab6_stride;                       // FOR LAB6 ONLY: the current stride of the process 
    uint32_t lab6_priority;                     // FOR LAB6 ONLY: the priority of process, set by lab6_set_priority(uint32_t)
};
```

然后我们看下rr算法的具体思想:RR调度算法的调度思想 是让所有runnable态的进程分时轮流使用CPU时间。RR调度器维护当前runnable进程的有序运行队列。当前进程的时间片用完之后，调度器将当前进程放置到运行队列的尾部，再从其头部取出进程进行调度。

RR_init初始化,初始化rq的run_list队列,然后设置运行队列中的数目

```c
static void
RR_init(struct run_queue *rq) {
    list_init(&(rq->run_list));
    rq->proc_num = 0;
}
```

RR_enqueue加入进程到rq的末尾,如果proc时间用完了要重置一下max_time_slice,然后指定好这个proc的rq是哪一个方便从proc struct反向找到rq,

```c
static void
RR_enqueue(struct run_queue *rq, struct proc_struct *proc) {
    assert(list_empty(&(proc->run_link)));
    list_add_before(&(rq->run_list), &(proc->run_link));
    if (proc->time_slice == 0 || proc->time_slice > rq->max_time_slice) {
        proc->time_slice = rq->max_time_slice;
    }
    proc->rq = rq;
    rq->proc_num ++;
}
```

RR_dequeue删除,删除就绪队列中的进程控制块指针

```c
static void
RR_dequeue(struct run_queue *rq, struct proc_struct *proc) {
    assert(!list_empty(&(proc->run_link)) && proc->rq == rq);
    list_del_init(&(proc->run_link));
    rq->proc_num --;
}
```

RR_pick_next来选下一个进程,选择下一个,然后判断不是自己本身,就是说存在proc在rq中,那么就返回proc

```c
static struct proc_struct *
RR_pick_next(struct run_queue *rq) {
    list_entry_t *le = list_next(&(rq->run_list));
    if (le != &(rq->run_list)) {
        return le2proc(le, run_link);
    }
    return NULL;
}
```

RR_proc_tick,大于0时,就-1,为0时就标记为可调度

```c
static void
RR_proc_tick(struct run_queue *rq, struct proc_struct *proc) {
    if (proc->time_slice > 0) {
        proc->time_slice --;
    }
    if (proc->time_slice == 0) {
        proc->need_resched = 1;
    }
}
```

最后完成函数接口的完成,实现了算法分离

```c
struct sched_class default_sched_class = {
    .name = "RR_scheduler",
    .init = RR_init,
    .enqueue = RR_enqueue,
    .dequeue = RR_dequeue,
    .pick_next = RR_pick_next,
    .proc_tick = RR_proc_tick,
};
```

## Part2 实现 Stride Scheduling 调度算法（需要编码）

首先将default_sched_stride_c中的内容覆盖default_sched.c的内容,然后我们需要完成ss算法的具体内容,然后我们看下ss算法的大概思路.

1. 为每个runnable的进程设置一个当前状态stride，表示该进程当前的调度权。另外定义其对应的pass值，表示对应进程在调度后，stride 需要进行的累加值。
2. 每次需要调度时，从当前 runnable 态的进程中选择 stride最小的进程调度。
3. 对于获得调度的进程P，将对应的stride加上其对应的步长pass（只与进程的优先权有关系）。
4. 在一段固定的时间之后，回到 2.步骤，重新调度当前stride最小的进程。
   可以证明，如果令 P.pass =BigStride / P.priority 其中 P.priority 表示进程的优先权（大于 1），而 BigStride 表示一个预先定义的大常数，则该调度方案为每个进程分配的时间将与其优先级成正比。

然后我们分别填充里面的函数

首先定义定义一个宏

```c
#define BIG_STRIDE 0x7FFFFFFF
```

然后他给我们提供了提个比较函数proc_stride_comp_f

```c
/* The compare function for two skew_heap_node_t's and the
 * corresponding procs*/
static int
proc_stride_comp_f(void *a, void *b) {
    // get a,b's proc struct
    struct proc_struct *p = le2proc(a, lab6_run_pool);
    struct proc_struct *q = le2proc(b, lab6_run_pool);
    // compare a and b's stride
    int32_t c = p->lab6_stride - q->lab6_stride;
    if (c > 0) return 1;
    else if (c == 0) return 0;
    else return -1;
}
```

rq中的lab6_run_pool是一个优先队列结构的,用来指向优先队列的头元素

然后我们实现第一个函数stride_init,初始化rq的run_list,然后将lab6_run_pool指向空

```c
/*
 * stride_init initializes the run-queue rq with correct assignment for
 * member variables, including:
 *
 *   - run_list: should be a empty list after initialization.
 *   - lab6_run_pool: NULL
 *   - proc_num: 0
 *   - max_time_slice: no need here, the variable would be assigned by the caller.
 *
 * hint: see libs/list.h for routines of the list structures.
 */
static void
stride_init(struct run_queue *rq) {
    /* LAB6: YOUR CODE
     * (1) init the ready process list: rq->run_list
     * (2) init the run pool: rq->lab6_run_pool
     * (3) set number of process: rq->proc_num to 0
     */
    list_init(&(rq->run_list));
    rq->lab6_run_pool = NULL;
    rq->proc_num = 0;
}
```

stride_enqueue

```c
/*
 * stride_enqueue inserts the process ``proc'' into the run-queue
 * ``rq''. The procedure should verify/initialize the relevant members
 * of ``proc'', and then put the ``lab6_run_pool'' node into the
 * queue(since we use priority queue here). The procedure should also
 * update the meta date in ``rq'' structure.
 *
 * proc->time_slice denotes the time slices allocation for the
 * process, which should set to rq->max_time_slice.
 *
 * hint: see libs/skew_heap.h for routines of the priority
 * queue structures.
 */
static void
stride_enqueue(struct run_queue *rq, struct proc_struct *proc) {
    /* LAB6: YOUR CODE
     * (1) insert the proc into rq correctly
     * NOTICE: you can use skew_heap or list. Important functions
     *         skew_heap_insert: insert a entry into skew_heap
     *         list_add_before: insert  a entry into the last of list
     * (2) recalculate proc->time_slice
     * (3) set proc->rq pointer to rq
     * (4) increase rq->proc_num
     */
#if USE_SKEW_HEAP
    rq->lab6_run_pool =
            skew_heap_insert(rq->lab6_run_pool, &(proc->lab6_run_pool), proc_stride_comp_f);
#else
    assert(list_empty(&(proc->run_link)));
     list_add_before(&(rq->run_list), &(proc->run_link));
#endif
    if (proc->time_slice == 0 || proc->time_slice > rq->max_time_slice) {
        proc->time_slice = rq->max_time_slice;
    }
    proc->rq = rq;
    rq->proc_num ++;
}
```

有个条件编译USE_SKEW_HEAP为1所以只执行if,这里是插入到优先队列中,然后判断时间片是否用完,如果是就重置

然后是删除stride_dequeue,删除优先队列中的

```c
/*
 * stride_dequeue removes the process ``proc'' from the run-queue
 * ``rq'', the operation would be finished by the skew_heap_remove
 * operations. Remember to update the ``rq'' structure.
 *
 * hint: see libs/skew_heap.h for routines of the priority
 * queue structures.
 */
static void
stride_dequeue(struct run_queue *rq, struct proc_struct *proc) {
    /* LAB6: YOUR CODE
     * (1) remove the proc from rq correctly
     * NOTICE: you can use skew_heap or list. Important functions
     *         skew_heap_remove: remove a entry from skew_heap
     *         list_del_init: remove a entry from the  list
     */
#if USE_SKEW_HEAP
    rq->lab6_run_pool =
            skew_heap_remove(rq->lab6_run_pool, &(proc->lab6_run_pool), proc_stride_comp_f);
#else
    assert(!list_empty(&(proc->run_link)) && proc->rq == rq);
     list_del_init(&(proc->run_link));
#endif
    rq->proc_num --;
}
```

stride_pick_next,因为是用优先队列所以可以用le2proc直接拿一下proc,如果优先级为0则设置一下步长,否则BIG_STRIDE / p->lab6_priority

```c
/*
 * stride_pick_next pick the element from the ``run-queue'', with the
 * minimum value of stride, and returns the corresponding process
 * pointer. The process pointer would be calculated by macro le2proc,
 * see kern/process/proc.h for definition. Return NULL if
 * there is no process in the queue.
 *
 * When one proc structure is selected, remember to update the stride
 * property of the proc. (stride += BIG_STRIDE / priority)
 *
 * hint: see libs/skew_heap.h for routines of the priority
 * queue structures.
 */
static struct proc_struct *
stride_pick_next(struct run_queue *rq) {
    /* LAB6: YOUR CODE
     * (1) get a  proc_struct pointer p  with the minimum value of stride
            (1.1) If using skew_heap, we can use le2proc get the p from rq->lab6_run_poll
            (1.2) If using list, we have to search list to find the p with minimum stride value
     * (2) update p;s stride value: p->lab6_stride
     * (3) return p
     */
#if USE_SKEW_HEAP
    if (rq->lab6_run_pool == NULL) return NULL;
    struct proc_struct *p = le2proc(rq->lab6_run_pool, lab6_run_pool);
#else
    list_entry_t *le = list_next(&(rq->run_list));

     if (le == &rq->run_list)
          return NULL;

     struct proc_struct *p = le2proc(le, run_link);
     le = list_next(le);
     while (le != &rq->run_list)
     {
          struct proc_struct *q = le2proc(le, run_link);
          if ((int32_t)(p->lab6_stride - q->lab6_stride) > 0)
               p = q;
          le = list_next(le);
     }
#endif
    if (p->lab6_priority == 0)
        p->lab6_stride += BIG_STRIDE;
    else p->lab6_stride += BIG_STRIDE / p->lab6_priority;
    return p;
}
```
最后是stride_proc_tick,差不多

```c
/*
 * stride_proc_tick works with the tick event of current process. You
 * should check whether the time slices for current process is
 * exhausted and update the proc struct ``proc''. proc->time_slice
 * denotes the time slices left for current
 * process. proc->need_resched is the flag variable for process
 * switching.
 */
static void
stride_proc_tick(struct run_queue *rq, struct proc_struct *proc) {
    /* LAB6: YOUR CODE */
    if (proc->time_slice > 0) {
        proc->time_slice --;
    }
    if (proc->time_slice == 0) {
        proc->need_resched = 1;
    }
}
```

最后make grade能过全部的测试说明可以了.

## 流程总结

这里没有太大的改变就是,添加了sched的算法分离的结构,然后有几个地方会调用到schedule这个函数,来进行到进程调度,然后我们看下在init.c中添加了一个sched_init();进行初始化调度结构,然后看下有几个调度点:

| 编号 | 位置              | 原因                                                         |
| ---- | ----------------- | ------------------------------------------------------------ |
| 1    | proc.c::do_exit   | 用户线程执行结束，主动放弃CPU控制权。                        |
| 2    | proc.c::do_wait   | 用户线程等待子进程结束，主动放弃CPU控制权。                  |
| 3    | proc.c::init_main | 1. initproc内核线程等待所有用户进程结束，如果没有结束，就主动放弃CPU控制权; 2. initproc内核线程在所有用户进程结束后，让kswapd内核线程执行10次，用于回收空闲内存资源 |
| 4    | proc.c::cpu_idle  | idleproc内核线程的工作就是等待有处于就绪态的进程或线程，如果有就调用schedule函数 |
| 5    | sync.h::lock      | 在获取锁的过程中，如果无法得到锁，则主动放弃CPU控制权        |
| 6    | trap.c::trap      | 如果在当前进程在用户态被打断去，且当前进程控制块的成员变量need_resched设置为1，则当前线程会放弃CPU控制权 |

主要就是主动放弃例如1,2,5,然后3,4,initproc内核线程等待用户进程结束而执行schedule函数；idle内核线程在没有进程处于就绪态时才执行，一旦有了就绪态的进程，它将执行schedule函数完成进程调度.最特殊的是6是trap来完成的进程切换,只有用户态的进程可以被打断,然后need_resched为1才行,类似一下代码

```c
if (!in_kernel) {
    ……

    if (current->need_resched) {
        schedule();
    }
}
```

# 总结

这个lab6还是比较简单的,但是最近太忙了并且有点累,就先写到这里吧