# 前言

接下来准备对整个ucore操作系统做一个总结，从他的整体架构，重点涉及，以及常见问题来进行一下分析总结，感觉这次做完整个ucore，对操作系统有了更加深刻的理解与认识．

# 正文

## Ucore中的一些重要设计思想

1. 面向对象OOP

   虽然ucore是用C语言来写的，但是它其中的一个很重要的思想就是面向对象，比如抽象出页置换机制，进程调度框架，vfs文件系统的设计等等，这些都是将不同子系统中的相似点进行统一抽象出一个接口，而这个接口中就包含了子系统必须完成的操作函数，而这个在C++中类似虚表，C++中我们会声明一个基类即抽象类，来提供给子系统需要的动作（PS:这里有个疑问，既然都面向对象了，为啥不直接用C++）

2. 采用双链表的数据结构

   在ucore中大量采用双向链表来存储对象，例如空闲内存块列表、内存页链表、进程列表、设备链表、文件系统列表等的数据组织，但是在ucore中没有在链表中保存数据成员，因为如果保存了数据成员的话，那么每次对链表的操作都会因为数据结构的不同而导致操作无法统一，所以我们使用类似的方法

   ```c
   struct Page {
       int ref;                        // page frame's reference counter
       uint32_t flags;                 // array of flags that describe the status of the page frame
       unsigned int property;          // the num of free block, used in first fit pm manager
       list_entry_t page_link;         // free list link
       list_entry_t pra_page_link;     // used for pra (page replace algorithm)
       uintptr_t pra_vaddr;            // used for pra (page replace algorithm)
   };
   ```

   将数据和链表结构存储在一个struct中，但是这样的话我们怎么才能根据链表指针来拿到这个struct内，我们参看一个lexxx结构，举个例子，我们怎么拿到某个Page

   ```c
   //free_area是空闲块管理结构，free_area.free_list是空闲块链表头
   free_area_t free_area;
   list_entry_t * le = &free_area.free_list;  //le是空闲块链表头指针
   while((le=list_next(le)) != &free_area.free_list) { //从第一个节点开始遍历
       struct Page *p = le2page(le, page_link); //获取节点所在基于Page数据结构的变量
       ……
   }
   ```

   看到我们先遍历链表，拿到相应指针后调用le2Page宏，le的意思是link entry，就是利用链表指针来转换为Page，然然后我们来跟进下这个宏

   ```c
   // convert list entry to page
   #define le2page(le, member)                 \
   to_struct((le), struct Page, member)
   ```

   继续跟进to_struct

   ```c
   /* Return the offset of 'member' relative to the beginning of a struct type */
   #define offsetof(type, member)                                      \
   ((size_t)(&((type *)0)->member))
   
   /* *
    * to_struct - get the struct from a ptr
    * @ptr:    a struct pointer of member
    * @type:   the type of the struct this is embedded in
    * @member: the name of the member within the struct
    * */
   #define to_struct(ptr, type, member)                               \
   ((type *)((char *)(ptr) - offsetof(type, member)))
   ```

   这里我直接用文档的内容解释了，比较清晰

   > 这里采用了一个利用gcc编译器技术的技巧，即先求得数据结构的成员变量在本宿主数据结构中的偏移量，然后根据成员变量的地址反过来得出属主数据结构的变量的地址。
   >
   > 我们首先来看offsetof宏，size_t最终定义与CPU体系结构相关，本实验都采用Intel X86-32 CPU，顾szie_t等价于 unsigned int。 ((type *)0)->member的设计含义是什么？其实这是为了求得数据结构的成员变量在本宿主数据结构中的偏移量。为了达到这个目标，首先将0地址强制"转换"为type数据结构（比如struct Page）的指针，再访问到type数据结构中的member成员（比如page_link）的地址，即是type数据结构中member成员相对于数据结构变量的偏移量。在offsetof宏中，这个member成员的地址（即“&((type *)0)->member)”）实际上就是type数据结构中member成员相对于数据结构变量的偏移量。对于给定一个结构，offsetof(type,member)是一个常量，to_struct宏正是利用这个不变的偏移量来求得链表数据项的变量地址。接下来再分析一下to_struct宏，可以发现 to_struct宏中用到的ptr变量是链表节点的地址，把它减去offsetof宏所获得的数据结构内偏移量，即就得到了包含链表节点的属主数据结构的变量的地址。

   总结来说就是，offsetof拿结构内指针偏移量，然后指针所指的地方减去偏移量就拿到Page结构的地址了

## 流程小结

这里我想简单的总结下整个ucore系统的流程，然后应该会忽略掉一些实现细节（毕竟我也记不住那么多东西Orz），

### 系统的加载

1. 计算机加电后，CPU从物理地址0xFFFFFFF0进行跳转到BIOS，然后BIOS首先进行硬件自检和初始化，读取引导扇区的内容到内存的0x7c00处，然后CPU跳转到bootloader继续执行

2. bootloader将80386从实模式切换到保护模式，主要工作是开启分段模式，从而有了特权级（max(RPL,CPL)<=DPL），GDT，逻辑地址，物理地址等概念，拓展了内存的寻址空间，然后bootloader会加载在硬盘中的ucore.img，然后会跳转到ucore的入口（kern/init.c中的kern_init函数的起始地址），再将CPU的控制权交给ucore

3. 加下来ucore会进行一些初始化设置，如设置中断向量表，初始化时钟中断，这里重点说下中断，因为我们后面很多重要概念都是利用中断来做的，比如特权级的切换．

   操作系统在IDT中设置好各种中断向量对应的中断描述符，留待CPU在产生中断后查询对应中断服务例程的起始地址。而IDT本身的起始地址保存在idtr寄存器中。我们利用中断向量表就能确定对应中断动作之后该由哪块代码逻辑继续处理了．中断的流程简单来说就是显示保存现场，将相关寄存器的信息压入trapframe的结构中，将当前栈顶的esp作为指针，传入trap函数来作为参数，然后根据中断号不同选择不同的中断，进行处理，结束后ret命令恢复栈中寄存器的值，重新设置esp指向中断返回的eip，最后iret恢复cs,eflag,eip继续执行．（这里可能有理解错误，还要再细细研究下）

### 物理内存的管理

1. bootloader修改后探测了物理内存的大小，修改了堆栈和段映射
2. 以固定页面大小来划分整个物理内存空间，并准备以此为最小内存分配单位来管理整个物理内存，管理在内核运行过程中每页内存，设定其可用状态（free的，used的，还是reserved的），
3. 接着ucore kernel就要建立页表， 启动分页机制，让CPU的MMU把预先建立好的页表中的页表项读入到TLB（快表）中，根据页表项描述的虚拟页（Page）与物理页帧（Page Frame）的对应关系完成CPU对内存的读、写和执行操作。

这里我们有pmm_mannger来进行物理内存页的框架管理，来作为怎么选择内存块，这里我们实现的是最简单的first fit．这里可以关注下buddy system的思路

### 虚拟内存管理

1. 因为物理内存是有限的，我们想要拓展内存怎么办，就可以利用虚拟内存的方法，用**时间换空间**，当程序只有确定需要页面时操作系统再动态地分配物理内存，建立虚拟内存到物理内存的页映射关系，而如何进行替换就是一个算法框架．

2. 整体的思路就是：

   > 首先完成初始化虚拟内存管理机制，即需要设置好哪些页需要放在物理内存中，哪些页不需要放在物理内存中，而是可被换出到硬盘上，并涉及完善建立页表映射、页访问异常处理操作等函数实现。然后就执行一组访存测试，看看我们建立的页表项是否能够正确完成虚实地址映射，是否正确描述了虚拟内存页在物理内存中还是在硬盘上，是否能够正确把虚拟内存页在物理内存和硬盘之间进行传递，是否正确实现了页面替换算法等。

3. 这里再关注下页置换算法

   如果在把硬盘中对应的数据或代码调入内存前，操作系统发现物理内存已经没有空闲空间了，这时操作系统必须把它认为“不常用”的页换出到磁盘上去，以腾出内存空闲空间给应用程序所需的数据或代码。所以我们的重点就是选择哪个页面置换出去，这里我们实现的是最简单的先进先出FIFO算法（该算法总是淘汰最先进入内存的页，即选择在内存中驻留时间最久的页予以淘汰）．而这里我们使用一个swap_manager的算法框架来抽象出具体的算法

### 内核线程管理

1. 我们用PCB进程控制块作为进程管理的单位，然后用双向链表来联系多个PCB，所以对于我们想要初始化内核线程的话，首先肯定是初始化个PCB．建立进程控制块（proc.c中的alloc_proc函数）后，现在就可以通过进程控制块来创建具体的进程/线程了
2. 然后我们创建0好内核线程idleproc,其作用是不停地查询，看是否有其他内核线程可以执行了，如果有，马上让调度器选择那个内核线程执行，然后利用kernel_thread一路调用do_fork复zhel1号内核线程initproc，initproc内核线程的工作就是显示“Hello World”
3. 我们idle最后执行的是cpu_idle，进行循环监听调度，这里的进程调度实现的是最简单的FIFO，后面我们会具体实现进程调度这块，注意这里做线程切换的时候有个在被打断线程栈顶保存trapframe的操作，这都是为了中断结束后返回恢复现场用的，在之后做特权级切换的时候非常重要．

### 用户线程的管理

1. 在这个lab中，我们是直接将应用程序ld链接到ucore程序里面的，同时记录了应用程序的起始地址和偏移量在全局变量中，方便后面将其进行加载到内存中，（只有后面的文件系统完成后才可以按照正常的方式来获取）
2. 对于如何创建一个用户线程，在这个lab中就是利用initproc调用init_main,然后执行KERNEL_EXECVE，调用到kernel_execve触发中断，从而最终调用到SYS_exec系统调用，然后将我们前面说的文件位置变量作为参数一路传递到do_execve函数，这个函数会首先为用户线程清空环境，做好准备，然后读取ELF文件等操作，
3. 这个主要是load_icode完成的，大概就是完成了进程块，页目录表等的初始化，根据ELF文件头信息建立好物理地址和虚拟地址的映射，然后把文件段中的内容拷贝到内核虚拟地址，之后设置好用户堆栈，然后更新页目录表到cr3寄存器中，最后清空进程的中断帧，重新设置中断帧，最后执行iret的时候能够成功让CPU切换到用户态（在我看来就是一些寄存器值和内存位置的改变）
4. 用户进行结束后，我们需要回收资源，由当前进程完成大部分的资源回收，然后父进程完成剩余资源的回收工作．do_exit是用户进程回收资源的主要函数，完成回收和表示自己可回收后，会唤醒父进程，调用schedule后选择新的进程执行，最后父进程会回收子进程的PCB等资源
5. 最后还有一个应用程序怎么调用系统函数呢，我们是利用中断来完成的，通过不同的中断信号，保存好用户进程的tf后即保存现场后，触发中断从用户态切换到内核态，最后完成后又原路返回，恢复寄存器的值，并设置好eip的指令位置．

### 调度器

1. 这里主要修改的是schedule中的内容，原来我们只是简单的FIFO对进程进行调度，这里我们类似前面一样抽象出一个调度框架，在这个框架下面我们再分别可以设计不同的调度算法

### 同步互斥

1. 这一部分解决是当多个进程想要访问或者改变同一资源变量的时候，我们怎么做处理，ucore的lab中分别用信号量和管程来实现了哲学家就餐问题，其中底层依靠的是：计时器，硬件中断屏蔽和使能，和等待队列
2. 对于管程的实现其实也是利用信号量完成的，类似一个临界区，一个管程同一时刻只能一个进程进入，管程里面维护了数据，然后进程可能因为条件变量不满足而挂在上面，等待者计时器超时遍历等待队列来唤醒等待队列中的进程

### 文件系统

1. 文件系统主要是做了四层，通用接口，vfs，sfs，外设驱动，每一层都类似一个抽象，对上提供接口，对下抽象实现
2. 目录也是文件，只不过可能是保存的inode对应的属性不同，inode包含了文件的各种属性，然后我们是根据路径从硬盘加载dfs_inode的信息到内存中，然后再继续操作文件的．

## 待补充完成的问题

1. buddy system基本设计

2. COW的设计

3. fork的流程

4. 死锁重入探测机制

   ．．．．．．

# 总结

大概花了两个多月的时间和ucore进行奋战，基本上每个周末都会把大半时间花在看代码上面，自我感觉整个的代码分析阅读能力提高了很多，但是想想那些设计开发操作系统的大牛是真的厉害，自己能力有限，目前只有那么多精力完成到这个地步，之后的学习工作中，会不断解决上面我遗留的问题，不过接下的日子我的重点应该会放在CMU的数据库上面，以及修复一下前面遗留的raft，还有就是手头实习上的一些事情．

道阻且长，加油．