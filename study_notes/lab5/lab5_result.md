# 前言

Lab5用户线程的相关内容，感觉是做到现在量最大的一次，要读的代码好多，再加上我摸鱼了一下，还有实习的一些事情，导致花了两个礼拜才搞定，现在让我们正式开始吧。

# 正文

## Part0

同样是利用clion的compare功能来将前面的代码填写到lab5中，但是这一次我们需要对几个地方进行修改根据注释，来满足我们lab5的实验要求。

首先是alloc_proc函数

```c++
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
        //LAB5 YOUR CODE : (update LAB4 steps)
        /*
         * below fields(add in LAB5) in proc_struct need to be initialized
         *       uint32_t wait_state;                        // waiting state
         *       struct proc_struct *cptr, *yptr, *optr;     // relations between processes
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
        proc->wait_state = 0;  // init process wait state
        proc->cptr = proc->optr = proc->yptr = NULL;  // init the pointers of processs
    }
    return proc;
}
```

添加了几个需要初始化的内容

```c++
proc->wait_state = 0;  // init process wait state
proc->cptr = proc->optr = proc->yptr = NULL;  // init the pointers of processs
```

这里说明下新增的指针的意思

```c++
parent:           proc->parent  (proc is children)
children:         proc->cptr    (proc is parent)
older sibling:    proc->optr    (proc is younger sibling)
younger sibling:  proc->yptr    (proc is older sibling)
```

然后是do_fork函数

```c++
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

    //LAB5 YOUR CODE : (update LAB4 steps)
    /* Some Functions
     *    set_links:  set the relation links of process.  ALSO SEE: remove_links:  lean the relation links of process
     *    -------------------
     *    update step 1: set child proc's parent to current process, make sure current process's wait_state is 0
     *    update step 5: insert proc_struct into hash_list && proc_list, set the relation links of process
     */
    if ((proc = alloc_proc()) == NULL) {  // allocate memory
        goto fork_out;
    }
    proc->parent = current;
    assert(current->wait_state == 0);// make sure process is waiting
    if (setup_kstack(proc) != 0) {  // allocate a kernel stack
        goto bad_fork_cleanup_proc;
    }
    if (copy_mm(clone_flags, proc) != 0) {  // clone parent's mm
        goto bad_fork_cleanup_kstack;
    }
    copy_thread(proc, stack, tf);  // setup tf and context eip and esp
    bool intr_flag;
    local_intr_save(intr_flag);  // make sure when adjust the memory data, it won't be interrupted according to eflag
    {
        proc->pid = get_pid();
        hash_proc(proc);  // add proc in hash list
        set_links(proc);  // lab5 set link about the process
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

添加了这两句

```c++
assert(current->wait_state == 0);// make sure process is waiting
```

修改从原来的简单计数，变成set_links来修改相关的进程

```c++
set_links(proc);  // lab5 set link about the process
```

然后是ide_init函数

```c++
/* idt_init - initialize IDT to each of the entry points in kern/trap/vectors.S */
void
idt_init(void) {
     /* LAB1 YOUR CODE : STEP 2 */
     /* (1) Where are the entry addrs of each Interrupt Service Routine (ISR)?
      *     All ISR's entry addrs are stored in __vectors. where is uintptr_t __vectors[] ?
      *     __vectors[] is in kern/trap/vector.S which is produced by tools/vector.c
      *     (try "make" command in lab1, then you will find vector.S in kern/trap DIR)
      *     You can use  "extern uintptr_t __vectors[];" to define this extern variable which will be used later.
      * (2) Now you should setup the entries of ISR in Interrupt Description Table (IDT).
      *     Can you see idt[256] in this file? Yes, it's IDT! you can use SETGATE macro to setup each item of IDT
      * (3) After setup the contents of IDT, you will let CPU know where is the IDT by using 'lidt' instruction.
      *     You don't know the meaning of this instruction? just google it! and check the libs/x86.h to know more.
      *     Notice: the argument of lidt is idt_pd. try to find it!
      */
     /* LAB5 YOUR CODE */
     //you should update your lab1 code (just add ONE or TWO lines of code), let user app to use syscall to get the service of ucore
     //so you should setup the syscall interrupt gate in here
    extern uintptr_t __vectors[];  //声明__vectors[]
    int i;
    for (i = 0; i < 256; i++) {
        SETGATE(idt[i], 0, GD_KTEXT, __vectors[i], DPL_KERNEL); //填充中断向量表
    }
    SETGATE(idt[T_SWITCH_TOK], 0, GD_KTEXT, __vectors[T_SWITCH_TOK], DPL_USER); //设置从用户态到内核态，注意这里的权限为DPL_USER
    SETGATE(idt[T_SYSCALL], 1, GD_KTEXT, __vectors[T_SYSCALL], DPL_USER); //lab5这里主要是设置相应的中断门
    lidt(&idt_pd);  //加载中断向量表到寄存器中
}
```

添加了一句，用来设置相应的中断门

```c++
SETGATE(idt[T_SYSCALL], 1, GD_KTEXT, __vectors[T_SYSCALL], DPL_USER); //lab5这里主要是设置相应的中断门
```

在上述代码中，可以看到在执行加载中断描述符表lidt指令前，专门设置了一个特殊的中断描述符idt[T_SYSCALL]，它的特权级设置为DPL_USER，中断向量处理地址在vectors[T_SYSCALL]处。这样建立好这个中断描述符后，一旦用户进程执行“INT T_SYSCALL”后，由于此中断允许用户态进程产生（注意它的特权级设置为DPL_USER），所以CPU就会从用户态切换到内核态，保存相关寄存器，并跳转到vectors[T_SYSCALL]处开始执行，形成如下执行路径： 
vector128(vectors.S)--\> 
\_\_alltraps(trapentry.S)--\>trap(trap.c)--\>trap\_dispatch(trap.c)----\>syscall(syscall.c)- 

然后是trap_dispatch函数

```c++
ticks++;
        if (ticks % TICK_NUM == 0) {
            assert(current != NULL);    // lab5 set process need be scheduled, means process's time is out
            current->need_resched = 1;
        }
```

多了句，将时间片设置为需要调度，说明当前进程的时间片已经用完了。

```c++
current->need_resched = 1;
```

## Part1 加载应用程序并执行

我们在练习一中需要完成的是load_icode函数，load_icode函数被do_exceve函数来调用的主要工作就是给用户进程建立一个能够让用户进程正常运行的用户环境。有一百多行，我不在这个部分进行详细分析，只说明下我们需要完成的那个部分。

```c++
/* LAB5:EXERCISE1 YOUR CODE
     * should set tf_cs,tf_ds,tf_es,tf_ss,tf_esp,tf_eip,tf_eflags
     * NOTICE: If we set trapframe correctly, then the user level process can return to USER MODE from kernel. So
     *          tf_cs should be USER_CS segment (see memlayout.h)
     *          tf_ds=tf_es=tf_ss should be USER_DS segment
     *          tf_esp should be the top addr of user stack (USTACKTOP)
     *          tf_eip should be the entry point of this binary program (elf->e_entry)
     *          tf_eflags should be set to enable computer to produce Interrupt
     */
    tf->tf_cs = USER_CS;
    tf->tf_ds = tf->tf_es = tf->tf_ss = USER_DS;
    tf->tf_esp = USTACKTOP;
    tf->tf_eip = elf->e_entry;
    tf->tf_eflags = FL_IF;
```

这里我们需要设置user进程的trapframe结构，以便当从内核态切换回用户态时，能根据tf中的信息来恢复用户线程的环境

这里我们可以看下添加用户线程后的内存分布结构

```c++
/* *
 * Virtual memory map:                                          Permissions
 *                                                              kernel/user
 *
 *     4G ------------------> +---------------------------------+
 *                            |                                 |
 *                            |         Empty Memory (*)        |
 *                            |                                 |
 *                            +---------------------------------+ 0xFB000000
 *                            |   Cur. Page Table (Kern, RW)    | RW/-- PTSIZE
 *     VPT -----------------> +---------------------------------+ 0xFAC00000
 *                            |        Invalid Memory (*)       | --/--
 *     KERNTOP -------------> +---------------------------------+ 0xF8000000
 *                            |                                 |
 *                            |    Remapped Physical Memory     | RW/-- KMEMSIZE
 *                            |                                 |
 *     KERNBASE ------------> +---------------------------------+ 0xC0000000
 *                            |        Invalid Memory (*)       | --/--
 *     USERTOP -------------> +---------------------------------+ 0xB0000000
 *                            |           User stack            |
 *                            +---------------------------------+
 *                            |                                 |
 *                            :                                 :
 *                            |         ~~~~~~~~~~~~~~~~        |
 *                            :                                 :
 *                            |                                 |
 *                            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 *                            |       User Program & Heap       |
 *     UTEXT ---------------> +---------------------------------+ 0x00800000
 *                            |        Invalid Memory (*)       | --/--
 *                            |  - - - - - - - - - - - - - - -  |
 *                            |    User STAB Data (optional)    |
 *     USERBASE, USTAB------> +---------------------------------+ 0x00200000
 *                            |        Invalid Memory (*)       | --/--
 *     0 -------------------> +---------------------------------+ 0x00000000
 * (*) Note: The kernel ensures that "Invalid Memory" is *never* mapped.
 *     "Empty Memory" is normally unmapped, but user programs may map pages
 *     there if desired.
 *
 * */
```

因为要切换回用户态tf->tf_cs为USER_CS;tf->tf_ds = tf->tf_es = tf->tf_ss = USER_DS;

tf_esp栈底为USTACKTOP也就是USERTOP，也就是0xB0000000放在用户栈顶，然后设置tf_eip指定好返回后cpu应该执行的命令，tf_eflags = FL_IF;表示允许中断

## Part2 父进程复制自己的内存空间给子进程

我们需要完成copy_range这个函数，其调用链接为

```c++
do_fork()---->copy_mm()---->dup_mmap()---->copy_range()
```

作用是赋值进程A的内存内容到内存B中，补充的代码如下

```c++
/* LAB5:EXERCISE2 YOUR CODE
             * replicate content of page to npage, build the map of phy addr of nage with the linear addr start
             *
             * Some Useful MACROs and DEFINEs, you can use them in below implementation.
             * MACROs or Functions:
             *    page2kva(struct Page *page): return the kernel vritual addr of memory which page managed (SEE pmm.h)
             *    page_insert: build the map of phy addr of an Page with the linear addr la
             *    memcpy: typical memory copy function
             *
             * (1) find src_kvaddr: the kernel virtual address of page
             * (2) find dst_kvaddr: the kernel virtual address of npage
             * (3) memory copy from src_kvaddr to dst_kvaddr, size is PGSIZE
             * (4) build the map of phy addr of  nage with the linear addr start
             */
void *kva_src = page2kva(page);  // get the parent's vpt address
void *kva_dst = page2kva(npage); // get the children's vpt address
memcpy(kva_dst, kva_src, PGSIZE);
ret = page_insert(to, npage, start, perm);
```

其实就是调用一个`memcpy`将父进程的内存直接复制给子进程。

到这里我们就完成了需要编程的部分，可以make qemu和make grade来看下结果

## Part3 阅读分析源代码，理解进程执行 fork/exec/wait/exit 的实现，以及系统调用的实现

具体的分析我想放在后面的流程总结中，这里只回答下两个思考题

### Q1 请分析fork/exec/wait/exit在实现中是如何影响进程的执行状态的？

①fork：执行完毕后，如果创建新进程成功，则出现两个进程，一个是子进程，一个是父进程。在子进程中，fork函数返回0，在父进程中，fork返回新创建子进程的进程ID。我们可以通过fork返回的值来判断当前进程是子进程还是父进程

②exit：会把一个退出码error_code传递给ucore，ucore通过执行内核函数do_exit来完成对当前进程的退出处理，主要工作简单地说就是回收当前进程所占的大部分内存资源，并通知父进程完成最后的回收工作。

③execve：完成用户进程的创建工作。首先为加载新的执行码做好用户态内存空间清空准备。接下来的一步是加载应用程序执行码到当前进程的新创建的用户态虚拟空间中。

④wait：等待任意子进程的结束通知。wait_pid函数等待进程id号为pid的子进程结束通知。这两个函数最终访问sys_wait系统调用接口让ucore来完成对子进程的最后回收工作

### Q2 请给出ucore中一个用户态进程的执行状态生命周期图（包执行状态，执行状态之间的变换关系，以及产生变换的事件或函数调用）

懒得画图了，，，老生长谈，进程的状态转化，等有空了再补，今天写不动了。

## 流程分析

### 用户线程的初始化及创建

这里我想完成的从头分析下整个lab5的流程，这样子更加有利于我们理解用户线程这个概念，我们接着lab4的内容来看，从proc_init()这个函数创建了第一个内核线程idleproc，然后idleproc用kernel_thread函数创建了init_main第二个内核线程，跟进到init_main函数中，发现其已经不是lab4中仅仅打印hello world，而是利用kernel_thread创建了user_main这个内核线程。

```c++
// init_main - the second kernel thread used to create user_main kernel threads
static int
init_main(void *arg) {
    size_t nr_free_pages_store = nr_free_pages();
    size_t kernel_allocated_store = kallocated();

    int pid = kernel_thread(user_main, NULL, 0);
    if (pid <= 0) {
        panic("create user_main failed.\n");
    }

    while (do_wait(0, NULL) == 0) {
        schedule();
    }

    cprintf("all user-mode processes have quit.\n");
    assert(initproc->cptr == NULL && initproc->yptr == NULL && initproc->optr == NULL);
    assert(nr_process == 2);
    assert(list_next(&proc_list) == &(initproc->list_link));
    assert(list_prev(&proc_list) == &(initproc->list_link));

    cprintf("init check memory pass.\n");
    return 0;
}
```

看下user_main这个函数，（实验指导书这里好像是没更新还是什么对不上代码）

```c++
// user_main - kernel thread used to exec a user program
static int
user_main(void *arg) {
#ifdef TEST
    KERNEL_EXECVE2(TEST, TESTSTART, TESTSIZE);
#else
    KERNEL_EXECVE(exit);
#endif
    panic("user_main execve failed.\n");
}
```

继续跟进KERNEL_EXECVE

```c++
#define __KERNEL_EXECVE(name, binary, size) ({                          \
            cprintf("kernel_execve: pid = %d, name = \"%s\".\n",        \
                    current->pid, name);                                \
            kernel_execve(name, binary, (size_t)(size));                \
        })

#define KERNEL_EXECVE(x) ({                                             \
            extern unsigned char _binary_obj___user_##x##_out_start[],  \
                _binary_obj___user_##x##_out_size[];                    \
            __KERNEL_EXECVE(#x, _binary_obj___user_##x##_out_start,     \
                            _binary_obj___user_##x##_out_size);         \
        })
```

能够看到继续调用__KERNEL_EXECVE，然后继续调用kernel_execve这个函数，

```c++
// kernel_execve - do SYS_exec syscall to exec a user program called by user_main kernel_thread
static int
kernel_execve(const char *name, unsigned char *binary, size_t size) {
    int ret, len = strlen(name);
    asm volatile (
    "int %1;"
    : "=a" (ret)
    : "i" (T_SYSCALL), "0" (SYS_exec), "d" (name), "c" (len), "b" (binary), "D" (size)
    : "memory");
    return ret;
}
```

看到这里里面的內联汇编，是调用指定SYS_exec系统调用，我们稍微回头看下其中的参数，能看到binary是`_binary_obj___user_##x##_out_start`,size是`_binary_obj___user_##x##_out_size`，这两个又是什么东西呢其实就是我们在makefile中ld将user目录下的用户程序拼接到ucore内核代码后，将起起始位置和大小存储在以上全局变量中，

然后int T_SYSCALL会触发中断（这个中断向量我们在part0中添加了），随后会触发调用链

```c++
vector128(vectors.S)-->
__alltraps(trapentry.S)-->trap(trap.c)-->trap_dispatch(trap.c)--
-->syscall(syscall.c)-->sys_exec（syscall.c）-->do_execve(proc.c)
```

可以看下trap_dispatch中

```c++
switch (tf->tf_trapno) {
    ...
    case T_SYSCALL:
        syscall();
    ...
```

当`tf->tf_trapno`为T_SYSCALL时会调用syscall()函数，这个tf是在__alltraps汇编中设置的pushl esp参数传递的也就算是我们上面的kernel_execve中的第八行，然后我们来跟进下syscall()函数是什么样的

```c++
void
syscall(void) {
    struct trapframe *tf = current->tf;
    uint32_t arg[5];
    int num = tf->tf_regs.reg_eax;
    if (num >= 0 && num < NUM_SYSCALLS) {
        if (syscalls[num] != NULL) {
            arg[0] = tf->tf_regs.reg_edx;
            arg[1] = tf->tf_regs.reg_ecx;
            arg[2] = tf->tf_regs.reg_ebx;
            arg[3] = tf->tf_regs.reg_edi;
            arg[4] = tf->tf_regs.reg_esi;
            tf->tf_regs.reg_eax = syscalls[num](arg);
            return ;
        }
    }
    print_trapframe(tf);
    panic("undefined syscall %d, pid = %d, name = %s.\n",
            num, current->pid, current->name);
}
```

可以看到它根据syscalls[num]的参数不同调用的函数也不一样

```c++
static int (*syscalls[])(uint32_t arg[]) = {
    [SYS_exit]              sys_exit,
    [SYS_fork]              sys_fork,
    [SYS_wait]              sys_wait,
    [SYS_exec]              sys_exec,
    [SYS_yield]             sys_yield,
    [SYS_kill]              sys_kill,
    [SYS_getpid]            sys_getpid,
    [SYS_putc]              sys_putc,
    [SYS_pgdir]             sys_pgdir,
};
```

然后根据编号，我们会调用sys_exec这个函数，其返回值会返回存到到reg_eax中。

然后我们来看sys_exec这个函数

```c++
static int
sys_exec(uint32_t arg[]) {
    const char *name = (const char *)arg[0];
    size_t len = (size_t)arg[1];
    unsigned char *binary = (unsigned char *)arg[2];
    size_t size = (size_t)arg[3];
    return do_execve(name, len, binary, size);
}
```

可以看到会调用do_execve函数，继续跟进

```c++
// do_execve - call exit_mmap(mm)&put_pgdir(mm) to reclaim memory space of current process
//           - call load_icode to setup new memory space accroding binary prog.
int
do_execve(const char *name, size_t len, unsigned char *binary, size_t size) {
    struct mm_struct *mm = current->mm;
    if (!user_mem_check(mm, (uintptr_t) name, len, 0)) {
        return -E_INVAL;
    }
    if (len > PROC_NAME_LEN) {
        len = PROC_NAME_LEN;
    }

    char local_name[PROC_NAME_LEN + 1];
    memset(local_name, 0, sizeof(local_name));
    memcpy(local_name, name, len);

    if (mm != NULL) {
        lcr3(boot_cr3);
        if (mm_count_dec(mm) == 0) {
            exit_mmap(mm);
            put_pgdir(mm);
            mm_destroy(mm);
        }
        current->mm = NULL;
    }
    int ret;
    if ((ret = load_icode(binary, size)) != 0) {
        goto execve_exit;
    }
    set_proc_name(current, local_name);
    return 0;

    execve_exit:
    do_exit(ret);
    panic("already exit: %e.\n", ret);
}
```

这个函数的主要作用就是

- user_mm_check来检测这个进程的正确性

- 首先为加载新的执行码做好用户态内存空间清空准备。如果mm不为NULL，则设置页表为内核空间页表，且进一步判断mm的引用计数减1后是否为0，如果为0，则表明没有进程再需要此进程所占用的内存空间，为此将根据mm中的记录，释放进程所占用户空间内存和进程页表本身所占空间。最后把当前进程的mm内存管理指针为空。由于此处的initproc是内核线程，所以mm为NULL，整个处理都不会做（这里存疑为什么current是initproc，应该是user_main这个内核线程吧）。
- 接下来的一步是加载应用程序执行码到当前进程的新创建的用户态虚拟空间中。这里涉及到读ELF格式的文件，申请内存空间，建立用户态虚存空间，加载应用程序执行码等。load_icode函数完成了整个复杂的工作。

这里主要就是load_icode函数，里面主要设计的就是

1. 调用mm_create函数来申请进程的内存管理数据结构mm所需内存空间，并对mm进行初始化；

2. 调用setup_pgdir来申请一个页目录表所需的一个页大小的内存空间，并把描述ucore内核虚空间映射的内核页表（boot_pgdir所指）的内容拷贝到此新目录表中，最后让mm->pgdir指向此页目录表，这就是进程新的页目录表了，且能够正确映射内核虚空间；

3. 根据应用程序执行码的起始位置来解析此ELF格式的执行程序，并调用mm_map函数根据ELF格式的执行程序说明的各个段（代码段、数据段、BSS段等）的起始位置和大小建立对应的vma结构，并把vma插入到mm结构中，从而表明了用户进程的合法用户态虚拟地址空间；

   3.6之后调用根据执行程序各个段的大小分配物理内存空间，并根据执行程序各个段的起始位置确定虚拟地址，并在页表中建立好物理地址和虚拟地址的映射关系，然后把执行程序各个段的内容拷贝到相应的内核虚拟地址中，至此应用程序执行码和数据已经根据编译时设定地址放置到虚拟内存中了；

4. 需要给用户进程设置用户栈，为此调用mm_mmap函数建立用户栈的vma结构，明确用户栈的位置在用户虚空间的顶端，大小为256个页，即1MB，并分配一定数量的物理内存且建立好栈的虚地址<-->物理地址映射关系；

5. 至此,进程内的内存管理vma和mm数据结构已经建立完成，于是把mm->pgdir赋值到cr3寄存器中，即更新了用户进程的虚拟内存空间，此时的initproc已经被hello的代码和数据覆盖，成为了第一个用户进程，但此时这个用户进程的执行现场还没建立好；

6. 先清空进程的中断帧，再重新设置进程的中断帧，使得在执行中断返回指令“iret”后，能够让CPU转到用户态特权级，并回到用户态内存空间，使用用户态的代码段、数据段和堆栈，且能够跳转到用户进程的第一条指令执行，并确保在用户态能够响应中断；

设置完这些东西后，一路返回到trapentry.S中的__trapret最后一句iret，从而切换到用户进程exit中第一句（位于user/libs/initcode.S的第三句），执行“IRET”指令后，CPU根据内核栈的情况回复到用户态，并把EIP指向tf_eip的值，即“INT T_SYSCALL”后的那条指令。

### 资源的回收

当执行完进程后，我们需要回收资源，当前线程会回收大部分，然后父进程会做最后的一部分，我们看user/exit.c中最后会调用一个exit()函数

```c++
#include <stdio.h>
#include <ulib.h>

int magic = -0x10384;

int
main(void) {
    int pid, code;
    cprintf("I am the parent. Forking the child...\n");
    if ((pid = fork()) == 0) {
        cprintf("I am the child.\n");
        yield();
        yield();
        yield();
        yield();
        yield();
        yield();
        yield();
        exit(magic);
    }
    else {
        cprintf("I am parent, fork a child pid %d\n",pid);
    }
    assert(pid > 0);
    cprintf("I am the parent, waiting now..\n");

    assert(waitpid(pid, &code) == 0 && code == magic);
    assert(waitpid(pid, &code) != 0 && wait() != 0);
    cprintf("waitpid %d ok.\n", pid);

    cprintf("exit pass.\n");
    return 0;
}
```

跟进下exit()函数

```c++
void
exit(int error_code) {
    sys_exit(error_code);
    cprintf("BUG: exit failed.\n");
    while (1);
}
```

调用了系统函数sys_exit函数

```c++
static int
sys_exit(uint32_t arg[]) {
    int error_code = (int)arg[0];
    return do_exit(error_code);
}
```

调用了do_exit函数，继续跟进

```c++
// do_exit - called by sys_exit
//   1. call exit_mmap & put_pgdir & mm_destroy to free the almost all memory space of process
//   2. set process' state as PROC_ZOMBIE, then call wakeup_proc(parent) to ask parent reclaim itself.
//   3. call scheduler to switch to other process
int
do_exit(int error_code) {
    if (current == idleproc) {
        panic("idleproc exit.\n");
    }
    if (current == initproc) {
        panic("initproc exit.\n");
    }

    struct mm_struct *mm = current->mm;
    if (mm != NULL) {
        lcr3(boot_cr3);
        if (mm_count_dec(mm) == 0) {
            exit_mmap(mm);
            put_pgdir(mm);
            mm_destroy(mm);
        }
        current->mm = NULL;
    }
    current->state = PROC_ZOMBIE;
    current->exit_code = error_code;

    bool intr_flag;
    struct proc_struct *proc;
    local_intr_save(intr_flag);
    {
        proc = current->parent;
        if (proc->wait_state == WT_CHILD) {
            wakeup_proc(proc);
        }
        while (current->cptr != NULL) {
            proc = current->cptr;
            current->cptr = proc->optr;

            proc->yptr = NULL;
            if ((proc->optr = initproc->cptr) != NULL) {
                initproc->cptr->yptr = proc;
            }
            proc->parent = initproc;
            initproc->cptr = proc;
            if (proc->state == PROC_ZOMBIE) {
                if (initproc->wait_state == WT_CHILD) {
                    wakeup_proc(initproc);
                }
            }
        }
    }
    local_intr_restore(intr_flag);

    schedule();
    panic("do_exit will not return!! %d.\n", current->pid);
}
```

do_exit回收了大部分资源，然后通知父进程完成最后所有的回收，大致流程如下：

1. 如果current->mm != NULL，表示是用户进程，则开始回收此用户进程所占用的用户态虚拟内存空间；

   a) 首先执行“lcr3(boot_cr3)”，切换到内核态的页表上，这样当前用户进程目前只能在内核虚拟地址空间执行了，这是为了确保后续释放用户态内存和进程页表的工作能够正常执行；

   b) 如果当前进程控制块的成员变量mm的成员变量mm_count减1后为0（表明这个mm没有再被其他进程共享，可以彻底释放进程所占的用户虚拟空间了。），则开始回收用户进程所占的内存资源：

   i. 调用exit_mmap函数释放current->mm->vma链表中每个vma描述的进程合法空间中实际分配的内存，然后把对应的页表项内容清空，最后还把页表所占用的空间释放并把对应的页目录表项清空；

   ii. 调用put_pgdir函数释放当前进程的页目录所占的内存；

   iii. 调用mm_destroy函数释放mm中的vma所占内存，最后释放mm所占内存；

   c) 此时设置current->mm为NULL，表示与当前进程相关的用户虚拟内存空间和对应的内存管理成员变量所占的内核虚拟内存空间已经回收完毕；

2. 这时，设置当前进程的执行状态current->state=PROC_ZOMBIE，当前进程的退出码current->exit_code=error_code。此时当前进程已经不能被调度了，需要此进程的父进程来做最后的回收工作（即回收描述此进程的内核栈和进程控制块）；

3. 如果当前进程的父进程current->parent处于等待子进程状态：

   current->parent->wait_state==WT_CHILD，

   则唤醒父进程（即执行“wakup_proc(current->parent)”），让父进程帮助自己完成最后的资源回收；

   ```c++
   void
   wakeup_proc(struct proc_struct *proc) {
       assert(proc->state != PROC_ZOMBIE);
       bool intr_flag;
       local_intr_save(intr_flag);
       {
           if (proc->state != PROC_RUNNABLE) {
               proc->state = PROC_RUNNABLE;
               proc->wait_state = 0;
           }
           else {
               warn("wakeup runnable process.\n");
           }
       }
       local_intr_restore(intr_flag);
   }
   ```

4. 如果当前进程还有子进程，则需要把这些子进程的父进程指针设置为内核线程initproc(我通俗点说就是爷爷进程)，且各个子进程指针需要插入到initproc的子进程链表中。如果某个子进程的执行状态是PROC_ZOMBIE，则需要唤醒initproc来完成对此子进程的最后回收工作。

5. 执行schedule()函数，选择新的进程执行。

那么父进程如何完成对子进程的最后回收工作呢？user_main这个进程结束后，唤醒了init_main这个进程，所以我们要看下init_main这个函数

```c++
while (do_wait(0, NULL) == 0) {
    schedule();
}
```

他会执行do_wait函数，我们来看下do_wait函数

```c++
// do_wait - wait one OR any children with PROC_ZOMBIE state, and free memory space of kernel stack
//         - proc struct of this child.
// NOTE: only after do_wait function, all resources of the child proces are free.
int
do_wait(int pid, int *code_store) {
    struct mm_struct *mm = current->mm;
    if (code_store != NULL) {
        if (!user_mem_check(mm, (uintptr_t) code_store, sizeof(int), 1)) {
            return -E_INVAL;
        }
    }

    struct proc_struct *proc;
    bool intr_flag, haskid;
    repeat:
    haskid = 0;
    if (pid != 0) {
        proc = find_proc(pid);
        if (proc != NULL && proc->parent == current) {
            haskid = 1;
            if (proc->state == PROC_ZOMBIE) {
                goto found;
            }
        }
    } else {
        proc = current->cptr;
        for (; proc != NULL; proc = proc->optr) {
            haskid = 1;
            if (proc->state == PROC_ZOMBIE) {
                goto found;
            }
        }
    }
    if (haskid) {
        current->state = PROC_SLEEPING;
        current->wait_state = WT_CHILD;
        schedule();
        if (current->flags & PF_EXITING) {
            do_exit(-E_KILLED);
        }
        goto repeat;
    }
    return -E_BAD_PROC;

    found:
    if (proc == idleproc || proc == initproc) {
        panic("wait idleproc or initproc.\n");
    }
    if (code_store != NULL) {
        *code_store = proc->exit_code;
    }
    local_intr_save(intr_flag);
    {
        unhash_proc(proc);
        remove_links(proc);
    }
    local_intr_restore(intr_flag);
    put_kstack(proc);
    kfree(proc);
    return 0;
}
```

这要求父进程要执行wait用户函数或wait_pid用户函数，这两个函数的区别是，wait函数等待任意子进程的结束通知，而wait_pid函数等待进程id号为pid的子进程结束通知。这两个函数最终访问sys_wait系统调用接口让ucore来完成对子进程的最后回收工作，即回收子进程的内核栈和进程控制块所占内存空间，具体流程如下：

1. 如果pid!=0，表示只找一个进程id号为pid的退出状态的子进程，否则找任意一个处于退出状态的子进程；
2. 如果此子进程的执行状态不为PROC_ZOMBIE，表明此子进程还没有退出，则当前进程只好设置自己的执行状态为PROC_SLEEPING，睡眠原因为WT_CHILD（即等待子进程退出），调用schedule()函数选择新的进程执行，自己睡眠等待，如果被唤醒，则重复跳回步骤1处执行；
3. 如果此子进程的执行状态为PROC_ZOMBIE，表明此子进程处于退出状态，需要当前进程（即子进程的父进程）完成对子进程的最终回收工作，即首先把子进程控制块从两个进程队列proc_list和hash_list中删除，并释放子进程的内核堆栈和进程控制块。自此，子进程才彻底地结束了它的执行过程，消除了它所占用的所有资源。

至此我们才完全的把一个进程的资源完全回收干净。

### 用户程序如何调用系统命令

如上面的过程，我们又是如何在用户程序中调用系统函数的呢，首先肯定是设置好中断向量表，也就是在part0中我们补充的，然后在user/lib库中user/libs/ulib.[ch]和user/libs/syscall.[ch]中完成了对访问系统调用的封装（懒得分析了，有空再补），最终调用的都是syscall即int T_SYSCALL，然后利用不同的寄存器来传参或者获得返回值。

最终的表格就是，与进程相关的各个系统调用属性如下所示

| 系统调用名 | 含义                                      | 具体完成服务的函数                                           |
| ---------- | ----------------------------------------- | ------------------------------------------------------------ |
| SYS_exit   | process exit                              | do_exit                                                      |
| SYS_fork   | create child process, dup mm              | do_fork-->wakeup_proc                                        |
| SYS_wait   | wait child process                        | do_wait                                                      |
| SYS_exec   | after fork, process execute a new program | load a program and refresh the mm                            |
| SYS_yield  | process flag itself need resecheduling    | proc->need_sched=1, then scheduler will rescheule this process |
| SYS_kill   | kill process                              | do_kill-->proc->flags \|= PF_EXITING, -->wakeup_proc-->do_wait-->do_exit |
| SYS_getpid | get the process's pid                     |                                                              |

 与用户态的函数库调用执行过程相比，系统调用执行过程的有四点主要的不同：

- 不是通过“CALL”指令而是通过“INT”指令发起调用；
- 不是通过“RET”指令，而是通过“IRET”指令完成调用返回；
- 当到达内核态后，操作系统需要严格检查系统调用传递的参数，确保不破坏整个系统的安全性；
- 执行系统调用可导致进程等待某事件发生，从而可引起进程切换；

其中的每个系统调用都类似我之前进行的分析。

# 总结 

累死我了算上代码7k多字，看的我头皮发麻，lab5的代码阅读量真的有点大，继续加油吧，还有三个lab就做完了，感觉最困难的部分已经被搞定了，冲冲冲。