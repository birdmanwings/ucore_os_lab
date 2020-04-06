# 前言

继续lab3，这里我们需要实现虚拟内存的部分，包括缺页处理和页面置换算法FIFO。现在让我们开始吧。

# 正文

## Part0

还是一样将Lab1和Lab2的我们写的代码填到Lab3中。

## Part1 给未被映射的地址映射上物理页

首先是两个重要的两个结构体,vma_struct，mm_struct，先看vma

```c
// the virtual continuous memory area(vma)
struct vma_struct {
    struct mm_struct *vm_mm; // the set of vma using the same PDT 
    uintptr_t vm_start;      //    start addr of vma    
    uintptr_t vm_end;        // end addr of vma
    uint32_t vm_flags;       // flags of vma
    list_entry_t list_link;  // linear list link which sorted by start addr of vma
};
```

vma指的是一段连续虚拟内存地址，vm_start，vm_end指的是连续虚拟内存的起始和结束地址，vm_flags是标志位，描述了这段地址的属性，包括：

- #define VM_READ 0x00000001   //只读
- #define VM_WRITE 0x00000002  //可读写
- #define VM_EXEC 0x00000004   //可执行

list_link是一个双向链表指针，将所有的vma链接起来，最后vm_mm是一个指向mm_struct的指针，vm_mm是一个更高层次的抽象概念，统领所有的vma，我们来看下mm_struct结构体

```c
// the control struct for a set of vma using the same PDT
struct mm_struct {
    list_entry_t mmap_list;        // linear list link which sorted by start addr of vma
    struct vma_struct *mmap_cache; // current accessed vma, used for speed purpose
    pde_t *pgdir;                  // the PDT of these vma
    int map_count;                 // the count of these vma
    void *sm_priv;                   // the private data for swap manager
};
```

mm包含所有虚拟内存的共同属性，mmap_list是一个双向链表，链接所有属于同一个页目录表的虚拟内存空间，mmap_cache是一个指向现在vma的指针，根据局部性定理可能复用，所以可以提高效率，pgdir指向共有的页目录，map_count记录有多少个vma，sm_priv指向用来链接记录页访问情况的链表头，是用来联系swap_manager。

do_pagefault处理页面异常的情况

- 目标页帧不存在（页表项全为0，即该线性地址与物理地址尚未建立映射或者已经撤销)；
- 相应的物理页帧不在内存中（页表项非空，但Present标志位=0，比如在swap分区或磁盘文件上)，这在本次实验中会出现，我们将在下面介绍换页机制实现时进一步讲解如何处理；
- 不满足访问权限(此时页表项P标志=1，但低权限的程序试图访问高权限的地址空间，或者有程序试图写只读页面).

根据注释填写练习一的代码，pgdir_alloc_page在pmm.c中定义。

```c
ptep = get_pte(mm->pgdir, addr, 1);
    if (ptep == NULL) { // 当页表不存在时
        cprintf("get_pte in do_pgfault function failed\n");
        goto failed;
    }
    if (*ptep == 0) {   // 物理地址不存在时
        if (pgdir_alloc_page(mm->pgdir, addr, perm) == NULL) {  // 申请物理页，并映射物理地址和逻辑地址
            cprintf("pgdir_alloc_page in do_pgfault function failed\n");
            goto failed;
        }
    }
```

make qemu后会看到check_pgfault() succeeded!
![](http://image.bdwms.com/FuAlf3UPDvi6QgxFsVgLNHmW1Rl8)

## Part2 补充完成基于FIFO的页面替换算法

首先补充玩do_pgfault中的部分，主要是设计到页面的换入，page_insert定义在pmm.c中，pra_vaddr为Page结构体中新添加的（pra_vaddr可以用来记录此物理页对应的虚拟页起始地址），swap_in，swap_map_swappable应该在swap.c中

```c
if (swap_init_ok) {
            struct Page *page = NULL;
            if ((ret = swap_in(mm, addr, &page)) != 0) {    // 将硬盘中的内容加载到page里面
                cprintf("swap_in in do_pgfault function failed\n");
                goto failed;
            }
            page_insert(mm->pgdir, page, addr, perm);   // 建立物理地址和逻辑地址的映射
            swap_map_swappable(mm, addr, page, 1);  // 指明这个页是可以交换的
            page->pra_vaddr = addr;                 // 注意Page结构里面新添加了一个pra_vaddr这个变量,用来指明换出内存的是哪个页
        } else {
            cprintf("no swap_init_ok but ptep is %x, failed\n", *ptep);
            goto failed;
        }
```

swap.h和swap.c中是维护了一个swap_manager的框架，而swap_fifo.h,c则是具体的fifo实现在这个manager框架下面。

然后我们需要完成在swap_fifo.c中的两个函数，首先是_fifo_map_swappable函数

```c
/*
 * (3)_fifo_map_swappable: According FIFO PRA, we should link the most recent arrival page at the back of pra_list_head qeueue
 */
static int
_fifo_map_swappable(struct mm_struct *mm, uintptr_t addr, struct Page *page, int swap_in)
{
    list_entry_t *head=(list_entry_t*) mm->sm_priv;
    list_entry_t *entry=&(page->pra_page_link);
 
    assert(entry != NULL && head != NULL);
    //record the page access situlation
    /*LAB3 EXERCISE 2: YOUR CODE*/ 
    //(1)link the most recent arrival page at the back of the pra_list_head qeueue.
    list_add(head, entry);
    return 0;
}
```

然后是_fifo_swap_out_victim根据前面记录的情况来挑选出需要换出的具体页面

```c
/*
 *  (4)_fifo_swap_out_victim: According FIFO PRA, we should unlink the  earliest arrival page in front of pra_list_head qeueue,
 *                            then assign the value of *ptr_page to the addr of this page.
 */
static int
_fifo_swap_out_victim(struct mm_struct *mm, struct Page **ptr_page, int in_tick) {
    list_entry_t *head = (list_entry_t *) mm->sm_priv;
    assert(head != NULL);
    assert(in_tick == 0);
    /* Select the victim */
    /*LAB3 EXERCISE 2: YOUR CODE*/
    //(1)  unlink the  earliest arrival page in front of pra_list_head qeueue
    //(2)  assign the value of *ptr_page to the addr of this page
    list_entry_t *le = head->prev;  // 注意这是个双向链表，这个prev指向了整个链表的最末尾了，就是最先插入的那个页面
    assert(le != head);
    struct Page *p = le2page(le, pra_page_link);
    list_del(le);
    assert(p != NULL);
    *ptr_page = p;
    return 0;
}
```

最后make qemu打印出check_swap() succeeded!说明实验成功

![](http://image.bdwms.com/FrGOpGwiyXl5iW-hFOgc_WgCOjYd)

## 流程总结

最后我再总结下本次lab的基本流程。都是从kern/init/init.c的的kern_init()函数开始，前面的都是跟lab1,2一样，直到vmm_init()函数调用check_vmm函数来检查vma和mm两个struct的正确性,ide_init()是设备的初始化，swap_init是交换初始化，其中swapfs_init初始化检测ide设备，然后声明swap_manager_fifo的struct的sm，然后调用check_swap()来正式的检查，check_swap是我们的主要检测函数。

1. 备份mem的env用作检测，检查mm,vma,pgdir等，从而产生一个mm的管理struct
2. 调用mm_create建立mm变量，并调用vma_create创建vma变量，设置合法的访问范围为4KB~24KB；
3. 调用free_page等操作，模拟形成一个只有4个空闲 physical page；并设置了从4KB~24KB的连续5个虚拟页的访问操作；
4. 设置记录缺页次数的变量pgfault_num=0，执行check_content_set函数，使得起始地址分别对起始地址为0x1000, 0x2000, 0x3000, 0x4000的虚拟页按时间顺序先后写操作访问，由于之前没有建立页表，所以会产生page fault异常，如果完成练习1，则这些从4KB~20KB的4虚拟页会与ucore保存的4个物理页帧建立映射关系；整个调用链为：访问测试，会触发缺页从而trap--> trap_dispatch-->pgfault_handler-->do_pgfault建立映射关系
5. 然后对虚页对应的新产生的页表项进行合法性检查；
6. 然后进入测试页替换算法的主体，执行函数check_content_access，并进一步调用到_fifo_check_swap函数，如果通过了所有的assert。这进一步表示FIFO页替换算法基本正确实现；
7. 恢复ucore环境。
8. 最后再检查mem的page是正确的，打印出check_swap() succeeded!

# 总结

直到感觉后面的实验比前面简单点，不过我是要吧具体的源码再仔细看下，接下来感觉可以提速了。

