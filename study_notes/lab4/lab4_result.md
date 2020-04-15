# 前言

lab4要求我们实现一个内核线程的初始化和调度

# 正文

## Part0

同样是利用Clion的compare功能直接将lab1,2,3的代码贴到lab4中

## Part1 分配并初始化一个进程控制块

我们先看下进程控制块PCB的结构

```c
struct proc_struct {
    enum proc_state state;                      // Process state
    int pid;                                    // Process ID
    int runs;                                   // the running times of Proces
    uintptr_t kstack;                           // Process kernel stack
    volatile bool need_resched;                 // bool value: need to be rescheduled to release CPU?
    struct proc_struct *parent;                 // the parent process
    struct mm_struct *mm;                       // Process's memory management field
    struct context context;                     // Switch here to run process
    struct trapframe *tf;                       // Trap frame for current interrupt
    uintptr_t cr3;                              // CR3 register: the base addr of Page Directroy Table(PDT)
    uint32_t flags;                             // Process flag
    char name[PROC_NAME_LEN + 1];               // Process name
    list_entry_t list_link;                     // Process link list 
    list_entry_t hash_link;                     // Process hash list
};
```

依次介绍各个参数的含义

- state:进程状态

  ```c
  // process's state in his life cycle
  enum proc_state {
      PROC_UNINIT = 0,  // uninitialized
      PROC_SLEEPING,    // sleeping
      PROC_RUNNABLE,    // runnable(maybe running)
      PROC_ZOMBIE,      // almost dead, and wait parent proc to reclaim his resource
  };
  ```

- pid:进程id

- runs:进程运行时间

- kstack:进程内核栈

- need_resched:是否需要调度

- parent:父进程

- mm:进程内存控制块，即lab3中控制虚拟内存的结构体，lab4中没有怎么涉及

- context:进程上下文环境，即一些寄存器

  ```c
  // Saved registers for kernel context switches.
  // Don't need to save all the %fs etc. segment registers,
  // because they are constant across kernel contexts.
  // Save all the regular registers so we don't need to care
  // which are caller save, but not the return register %eax.
  // (Not saving %eax just simplifies the switching code.)
  // The layout of context must match code in switch.S.
  struct context {
      uint32_t eip;
      uint32_t esp;
      uint32_t ebx;
      uint32_t ecx;
      uint32_t edx;
      uint32_t esi;
      uint32_t edi;
      uint32_t ebp;
  };
  ```

- tf:中断帧指针，用来存储进程的中断前的状态，因为ucore可以嵌套，所以在进程esp位置后维护了中断链

- cr3:指向一级页表，也就是页目录

- flags:进程标志位

- name:进程的名字

- list_link:进程用一个双向链表来存储

- hash_link:当进程很多的时候遍历双向链表效率肯定会很慢，所以维护了一个hash链表用来寻找对应的进程

然后我们要实现的alloc_page()函数要求分配一个proc_struct结构，就是简单的初始化一些数据，代码如下

```c
// alloc_proc - alloc a proc_struct and init all fields of proc_struct
static struct proc_struct *
alloc_proc(void) {
    struct proc_struct *proc = kmalloc(sizeof(struct proc_struct));
    if (proc != NULL) {
        //LAB4:EXERCISE1 YOUR CODE
        /*
         * below fields in proc_struct need to be initialized
         *       enum proc_state state;                      // Process state
         *       int pid;                                    // Process ID
         *       int runs;                                   // the running times of Proces
         *       uintptr_t kstack;                           // Process kernel stack
         *       volatile bool need_resched;                 // bool value: need to be rescheduled to release CPU?
         *       struct proc_struct *parent;                 // the parent process
         *       struct mm_struct *mm;                       // Process's memory management field
         *       struct context context;                     // Switch here to run process
         *       struct trapframe *tf;                       // Trap frame for current interrupt
         *       uintptr_t cr3;                              // CR3 register: the base addr of Page Directroy Table(PDT)
         *       uint32_t flags;                             // Process flag
         *       char name[PROC_NAME_LEN + 1];               // Process name
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
    }
    return proc;
}
```

## Part2 为新创建的内核线程分配资源 

do_fork过程：

1.分配并初始化进程控制块（alloc_proc 函数）;
2.分配并初始化内核栈（setup_stack 函数）;
3.根据 clone_flag标志复制或共享进程内存管理结构（copy_mm 函数）;
4.设置进程在内核（将来也包括用户态）正常运行和调度所需的中断帧和执行上下文 
（copy_thread函数）;
5.把设置好的进程控制块放入hash_list 和proc_list 两个全局进程链表中;
6.自此,进程已经准备好执行了，把进程状态设置为“就绪”态;
7.设置返回码为子进程的 id号。

```c
/* do_fork -     parent process for a new child process
 * @clone_flags: used to guide how to clone the child process
 * @stack:       the parent's user stack pointer. if stack==0, It means to fork a kernel thread.
 * @tf:          the trapframe info, which will be copied to child process's proc->tf
 */
int
do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf) {
    int ret = -E_NO_FREE_PROC;
    struct proc_struct *proc;
    if (nr_process >= MAX_PROCESS) {
        goto fork_out;
    }
    ret = -E_NO_MEM;
    //LAB4:EXERCISE2 YOUR CODE
    /*
     * Some Useful MACROs, Functions and DEFINEs, you can use them in below implementation.
     * MACROs or Functions:
     *   alloc_proc:   create a proc struct and init fields (lab4:exercise1)
     *   setup_kstack: alloc pages with size KSTACKPAGE as process kernel stack
     *   copy_mm:      process "proc" duplicate OR share process "current"'s mm according clone_flags
     *                 if clone_flags & CLONE_VM, then "share" ; else "duplicate"
     *   copy_thread:  setup the trapframe on the  process's kernel stack top and
     *                 setup the kernel entry point and stack of process
     *   hash_proc:    add proc into proc hash_list
     *   get_pid:      alloc a unique pid for process
     *   wakeup_proc:  set proc->state = PROC_RUNNABLE
     * VARIABLES:
     *   proc_list:    the process set's list
     *   nr_process:   the number of process set
     */

    //    1. call alloc_proc to allocate a proc_struct
    //    2. call setup_kstack to allocate a kernel stack for child process
    //    3. call copy_mm to dup OR share mm according clone_flag
    //    4. call copy_thread to setup tf & context in proc_struct
    //    5. insert proc_struct into hash_list && proc_list
    //    6. call wakeup_proc to make the new child process RUNNABLE
    //    7. set ret vaule using child proc's pid
    if ((proc = alloc_proc()) == NULL) {  // allocate memory
        goto fork_out;
    }
    proc->parent = current;
    if (setup_kstack(proc) != 0) {  // allocate a kernel stack
        goto bad_fork_cleanup_proc;
    }
    if (copy_mm(clone_flags, proc) != 0) {  // clone parent's mm
        goto bad_fork_cleanup_kstack;
    }
    copy_thread(proc, stack, tf);  // setup tf and context eip and esp
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        proc->pid = get_pid();
        hash_proc(proc);  // add proc in hash list
        list_add(&proc_list, &(proc->list_link));  // add proc into proc list
        nr_process++;
    }
    local_intr_restore(intr_flag);
    wakeup_proc(proc);  // wake up proc
    ret = proc->pid;  // return child proc's pid

    fork_out:
    return ret;

    bad_fork_cleanup_kstack:
    put_kstack(proc);
    bad_fork_cleanup_proc:
    kfree(proc);
    goto fork_out;
}
```

## Part3 阅读代码，理解 proc_run 函数和它调用的函数如何完成进程切换的。

首先proc_init()中初始化好了idleproc进程，并分配好了initproc的内存堆栈等环境，并设置了进程idleproc的need_resched位为1表示需要被调度，然后在cpu_idle()中一直循环看need_resched是否为1，然后调用schedule函数

```c
void
schedule(void) {
    bool intr_flag;
    list_entry_t *le, *last;
    struct proc_struct *next = NULL;
    local_intr_save(intr_flag);
    {
        current->need_resched = 0;
        last = (current == idleproc) ? &proc_list : &(current->list_link);
        le = last;
        do {  // find the fist proc that state is PROC_RUNNABLE
            if ((le = list_next(le)) != &proc_list) {
                next = le2proc(le, list_link);
                if (next->state == PROC_RUNNABLE) {
                    break;
                }
            }
        } while (le != last);
        if (next == NULL || next->state != PROC_RUNNABLE) {
            next = idleproc;
        }
        next->runs ++;
        if (next != current) {  // if find the next proc that is different from current proc
            proc_run(next);
        }
    }
    local_intr_restore(intr_flag);
}
```

local_intr_save,local_intr_restore两个分别是用来屏蔽中断和使能中断，然后在主要部分是首先设置当前进程的need_resched为0，然后在proc_list中寻找第一个state为PROC_RUNNABLE的，没找到就重新指向idleproc,run++，如果找到就调用proc_run函数进行切换。

```c
// proc_run - make process "proc" running on cpu
// NOTE: before call switch_to, should load  base addr of "proc"'s new PDT
void
proc_run(struct proc_struct *proc) {
    if (proc != current) {
        bool intr_flag;
        struct proc_struct *prev = current, *next = proc;
        local_intr_save(intr_flag);
        {
            current = proc;
            load_esp0(next->kstack + KSTACKSIZE);    // set the esp0 in ts point to next proc stack's top for trap, interrupt etc.
            lcr3(next->cr3);                               // set the value ine cr3 reg to next proc, it means change the page table
            switch_to(&(prev->context), &(next->context)); // switch the context between two proc
        }
        local_intr_restore(intr_flag);
    }
}
```

然后具体看下proc_run，同样先屏蔽中断，然后load_esp0设置任务状态段ts的esp0指针指向next proc的内核栈顶，这个主要是为了保存中断信息，当出现特权切换的时候（从特权态0<-->特权态3，或从特权态3<-->特权态3），正确定位处于特权态0时进程的内核栈的栈顶，而这个栈顶其实放了一个trapframe结构的内存空间，当中断结束时会根据这个保存信息恢复到中断前的状态。

lcr3用来切换页表，将cr3寄存器的值替换为next proc的cr3值，但是因为在lab4时idleproc和initproc共用一个内核页表boot_cr3，所以这里其实是无效的。

最后switch_to用来切换两个进程的context

```c
.text
.globl switch_to
switch_to:                      # switch_to(from, to)

    # save from's registers
    movl 4(%esp), %eax          # eax points to from
    popl 0(%eax)                # save eip !popl
    movl %esp, 4(%eax)          # save esp::context of from
    movl %ebx, 8(%eax)          # save ebx::context of from
    movl %ecx, 12(%eax)         # save ecx::context of from
    movl %edx, 16(%eax)         # save edx::context of from
    movl %esi, 20(%eax)         # save esi::context of from
    movl %edi, 24(%eax)         # save edi::context of from
    movl %ebp, 28(%eax)         # save ebp::context of from

    # restore to's registers
    movl 4(%esp), %eax          # not 8(%esp): popped return address already
                                # eax now points to to
    movl 28(%eax), %ebp         # restore ebp::context of to
    movl 24(%eax), %edi         # restore edi::context of to
    movl 20(%eax), %esi         # restore esi::context of to
    movl 16(%eax), %edx         # restore edx::context of to
    movl 12(%eax), %ecx         # restore ecx::context of to
    movl 8(%eax), %ebx          # restore ebx::context of to
    movl 4(%eax), %esp          # restore esp::context of to

    pushl 0(%eax)               # push eip

    ret
```

保存前一个进程的执行现场，前两条汇编指令（如下所示）保存了进程在返回switch_to函数后的指令地址到context.eip中

在接下来的7条汇编指令完成了保存前一个进程的其他7个寄存器到context中的相应成员变量中。至此前一个进程的执行现场保存完毕。再往后是恢复向一个进程的执行现场。

最后的pushl 0(%eax)其实把 context 中保存的下一个进程要执行的指令地址 context.eip 放到了堆栈顶，这样接下来执行最后一条指令“ret”时,会把栈顶的内容赋值给 EIP 寄存器，这样就切换到下一个进程执行了，即当前进程已经是下一个进程了，从而完成了进程的切换。

initproc初始化时设置了initproc->context.eip = (uintptr_t)forkret，这样，当执行switch_to函数并返回后，initproc将执行其实际上的执行入口地址forkret。

```c
    # return falls through to trapret...
.globl __trapret
__trapret:
    # restore registers from stack
    popal

    # restore %ds, %es, %fs and %gs
    popl %gs
    popl %fs
    popl %es
    popl %ds

    # get rid of the trap number and error code
    addl $0x8, %esp
    iret

.globl forkrets
forkrets:
    # set stack to this new process's trapframe
    movl 4(%esp), %esp
    jmp __trapret
```

forkrets函数首先把esp指向当前进程的中断帧，从_trapret开始执行到iret前，esp指向了current->tf.tf_eip，而如果此时执行的是initproc，则current->tf.tf_eip=kernel_thread_entry，kernel_thread_entry函数

```c
.text
.globl kernel_thread_entry
kernel_thread_entry:        # void kernel_thread(void)

    pushl %edx              # push arg
    call *%ebx              # call fn

    pushl %eax              # save the return value of fn(arg)
    call do_exit            # call do_exit to terminate current thread
```

call ebx调用fn函数即init_main即打印字符。

## 流程总结

从kern/init/init.c中来看

1. pmm_init() 

   (1) 初始化物理内存管理器。
   (2) 初始化空闲页，主要是初始化物理页的 Page 数据结构，以及建立页目录表和页表。
   (3) 初始化 boot_cr3 使之指向了 ucore 内核虚拟空间的页目录表首地址，即页目录的起始物理地址。
   (4) 初始化第一个页表 boot_pgdir。
   (5) 初始化了GDT，即全局描述符表。

2. pic_init() 

   初始化8259A中断控制器

3. idt_init() 

   初始化IDT，即中断描述符表

4. vmm_init() 

   主要就是实验了一个 do_pgfault()函数达到页错误异常处理功能，以及虚拟内存相关的 mm,vma 结构数据的创建/销毁/查找/插入等函数

5. proc_init() 

   这个函数启动了创建内核线程的步骤,完成了 idleproc 内核线程和 initproc 内核线程的创建或复制工作，分配好了内存堆栈空间等信息。

6. ide_init() 

   完成对用于页换入换出的硬盘(简称 swap 硬盘)的初始化工作

7. swap_init() 

   swap_init() 函数首先建立完成页面替换过程的主要功能模块，即 swap_manager ,其中包含了页面置换算法的实现

8. clock_init()

   时钟初始化

9. intr_enable()

   开启中断

10. cpu_idle()

    用来从idleproc切换到initproc

然后我们来看proc_init()

```c
// proc_init - set up the first kernel thread idleproc "idle" by itself and 
//           - create the second kernel thread init_main
void
proc_init(void) {
    int i;

    list_init(&proc_list);
    for (i = 0; i < HASH_LIST_SIZE; i++) {
        list_init(hash_list + i);
    }

    if ((idleproc = alloc_proc()) == NULL) {
        panic("cannot alloc idleproc.\n");
    }

    idleproc->pid = 0;
    idleproc->state = PROC_RUNNABLE;
    idleproc->kstack = (uintptr_t) bootstack;  // set the kernel addr for idle
    idleproc->need_resched = 1;  // if the need_resched = 1, cpu_idle will schedule another proc
    set_proc_name(idleproc, "idle");
    nr_process++;

    current = idleproc;

    int pid = kernel_thread(init_main, "Hello world!!", 0);
    if (pid <= 0) {
        panic("create init_main failed.\n");
    }

    initproc = find_proc(pid);
    set_proc_name(initproc, "init");

    assert(idleproc != NULL && idleproc->pid == 0);
    assert(initproc != NULL && initproc->pid == 1);
}
```

建立hash表，alloc_proc分配空间kmalloc，设置pid,state,kstack,need_resched，kstack直接使用内核栈，need_resched表示需要被调度，然后kernel_thread进行init proc的复制

```c
// kernel_thread - create a kernel thread using "fn" function
// NOTE: the contents of temp trapframe tf will be copied to 
//       proc->tf in do_fork-->copy_thread function
int
kernel_thread(int (*fn)(void *), void *arg, uint32_t clone_flags) {
    struct trapframe tf;
    memset(&tf, 0, sizeof(struct trapframe));
    tf.tf_cs = KERNEL_CS;
    tf.tf_ds = tf.tf_es = tf.tf_ss = KERNEL_DS;
    tf.tf_regs.reg_ebx = (uint32_t) fn;
    tf.tf_regs.reg_edx = (uint32_t) arg;
    tf.tf_eip = (uint32_t) kernel_thread_entry;
    return do_fork(clone_flags | CLONE_VM, 0, &tf);
}
```

创建tf指针保存中断信息并传递给do_fork函数，先设置代码段和数据段，指明initproc开始执行的地址tf_eip为kernel_thread_entry，然后看下这个函数

```c
.text
.globl kernel_thread_entry
kernel_thread_entry:        # void kernel_thread(void)

    pushl %edx              # push arg
    call *%ebx              # call fn

    pushl %eax              # save the return value of fn(arg)
    call do_exit            # call do_exit to terminate current thread
```

push %edx将fn函数的参数压栈，call *%ebx调用fn函数,push %eax将结果保存在eax，最后调用do_exit函数但是lab4没有涉及do_exit

然后看下do_fork，这个是主要创建复制进程的函数

```c
/* do_fork -     parent process for a new child process
 * @clone_flags: used to guide how to clone the child process
 * @stack:       the parent's user stack pointer. if stack==0, It means to fork a kernel thread.
 * @tf:          the trapframe info, which will be copied to child process's proc->tf
 */
int
do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf) {
    int ret = -E_NO_FREE_PROC;
    struct proc_struct *proc;
    if (nr_process >= MAX_PROCESS) {
        goto fork_out;
    }
    ret = -E_NO_MEM;
    
    if ((proc = alloc_proc()) == NULL) {  // allocate memory
        goto fork_out;
    }
    proc->parent = current;
    if (setup_kstack(proc) != 0) {  // allocate a kernel stack
        goto bad_fork_cleanup_proc;
    }
    if (copy_mm(clone_flags, proc) != 0) {  // clone parent's mm
        goto bad_fork_cleanup_kstack;
    }
    copy_thread(proc, stack, tf);  // setup tf and context eip and esp
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        proc->pid = get_pid();
        hash_proc(proc);  // add proc in hash list
        list_add(&proc_list, &(proc->list_link));  // add proc into proc list
        nr_process++;
    }
    local_intr_restore(intr_flag);
    wakeup_proc(proc);  // wake up proc
    ret = proc->pid;  // return child proc's pid

    fork_out:
    return ret;

    bad_fork_cleanup_kstack:
    put_kstack(proc);
    bad_fork_cleanup_proc:
    kfree(proc);
    goto fork_out;
}
```

1. 分配并初始化进程控制块（alloc_proc函数）；
2. 分配并初始化内核栈（setup_stack函数）；
3. 根据clone_flag标志复制或共享进程内存管理结构（copy_mm函数）；
4. 设置进程在内核（将来也包括用户态）正常运行和调度所需的中断帧和执行上下文（copy_thread函数）；
5. 把设置好的进程控制块放入hash_list和proc_list两个全局进程链表中；
6. 自此，进程已经准备好执行了，把进程状态设置为“就绪”态；
7. 设置返回码为子进程的id号。

主要看copy_thread函数

```c
// copy_thread - setup the trapframe on the  process's kernel stack top and
//             - setup the kernel entry point and stack of process
static void
copy_thread(struct proc_struct *proc, uintptr_t esp, struct trapframe *tf) {
    proc->tf = (struct trapframe *) (proc->kstack + KSTACKSIZE) - 1;
    *(proc->tf) = *tf;
    proc->tf->tf_regs.reg_eax = 0;  // set the return value after child proc/thread finished
    proc->tf->tf_esp = esp;
    proc->tf->tf_eflags |= FL_IF;  // FL_IF means this child proc can be trapped

    proc->context.eip = (uintptr_t) forkret;  // set the next command in the last interrupt
    proc->context.esp = (uintptr_t) (proc->tf);  // set the esp in the last interrupt
}
```

先在新建的进程中分配用来存储中断帧的栈空间，拷贝在kernel_thread中创建的tf到新进程中断帧栈中，设置好esp栈顶指针和eflag位置，eflag表示允许中断，即ucore允许嵌套中断，然后设置init proc的context，当context设置好，ucore切换到底init proc时就需要根据context来执行context.eip存储上次中断之后执行的下一个命令，esp为中断后的栈，但是init proc没有执行过，所以这就是第一次执行的命令和堆栈地址，init proc的执行函数为forkret（处理do_fork函数返回的工作）

```c
    # return falls through to trapret...
.globl __trapret
__trapret:
    # restore registers from stack
    popal

    # restore %ds, %es, %fs and %gs
    popl %gs
    popl %fs
    popl %es
    popl %ds

    # get rid of the trap number and error code
    addl $0x8, %esp
    iret

.globl forkrets
forkrets:
    # set stack to this new process's trapframe
    movl 4(%esp), %esp
    jmp __trapret
```

esp指向当前进程的中断帧，然后这个中断帧就是在kernel_thread函数中声明的`tf.tf_eip = (uint32_t) kernel_thread_entry;`当调用kernle_thread_entry就是调用fn，即init main

然后我们继续看，do_fork返回initproc的pid一路往上传递会proc_init函数，最后设置好name等一些不重要的信息，proc_init()结束

kern_init中调用cpu_idle就是我们part3完成的这里不再赘述。

# 总结

低估了难度和我的懒度。。。多花了两天才搞定的，我好菜啊，挣扎中。

