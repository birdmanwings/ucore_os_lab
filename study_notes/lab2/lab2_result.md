# 前言

继续lab2，大概算了下我应该至少每周一个lab，才能在两个月之内做完，感觉必须要加速了，不能再摸鱼了，毕竟不止一个ucore要学习，刚把爹，冲冲冲，注意一定要把[实验指导书](https://chyyuu.gitbooks.io/ucore_os_docs/content/lab2.html)相关部分认真的看完！！！

# 正文

## Part0

文件比较，我直接用clion自带的文件比较功能了，trap.c和kdebug.c两个文件改一下就可以了，复制lab1添的代码过去就行了。

## Part1 实现first-fit连续物理内存分配算法

物理页架构，整个物理内存管理都是以页（Page这个结构存储了信息）作为最小单位管理的

```c
/* *
 * struct Page - Page descriptor structures. Each Page describes one
 * physical page. In kern/mm/pmm.h, you can find lots of useful functions
 * that convert Page to other data types, such as phyical address.
 * */
struct Page {
    int ref;                        // page frame's reference counter
    uint32_t flags;                 // array of flags that describe the status of the page frame
    unsigned int property;          // the num of free block, used in first fit pm manager
    list_entry_t page_link;         // free list link
};
```

- ref：这个物理页被虚拟页映射的数目

- flags：有两位，一个是PG_reserved在pmm_init` (in pmm.c)中已经被设定了，表示是否保留，PG_property需要自己设定代表了（设置的宏在memlayout.h中SetPageProperty），这个物理页是否可用，0表示被分配了或者不是头空闲页，1表示是头空闲页并且是free的

- property：记录空闲内存快的数量，只有Page是第一个时才设定，否则如果free则设定为0

- page_link：链接连续内存快的指针，在list.h中定义

  ```c
  struct list_entry {
      struct list_entry *prev, *next;
  };
  
  typedef struct list_entry list_entry_t;
  ```

然后是一个双向链表

```c
/* free_area_t - maintains a doubly linked list to record free (unused) pages */
typedef struct {
    list_entry_t free_list;         // the list header
    unsigned int nr_free;           // # of free pages in this free list
} free_area_t;
```

- free_list：双向链表指针
- nr_free：当前空闲页的数目

然后正式开始我们的练习1

### default_init

首先是default_init的函数，已经实现好了，init函数就是用来初始化free_area变量的

```c
/* 
 *`free_list` is used to record the free memory blocks.
 * `nr_free` is the total number of the free memory blocks.
*/
static void
default_init(void) {
    list_init(&free_list);
    nr_free = 0;
}
```

### default_init_memmap

之后是default_init_memmap函数，是用来初始化某个双向链表的节点

会用到一些宏，变量

这个宏是用来设定flag的PG_property为1，即表明这个块为free的

```c
#define SetPageProperty(page)       set_bit(PG_property, &((page)->flags))
```

free_area就是上面那个free_area_t struct，里面有一个双向链表的指针，一个记录空闲块数量的nr_free

```c
free_area_t free_area;

#define free_list (free_area.free_list)
#define nr_free (free_area.nr_free)
```

原来的函数

```c
default_init_memmap(struct Page *base, size_t n) {
    assert(n > 0);
    struct Page *p = base;
    for (; p != base + n; p ++) {
        assert(PageReserved(p));
        p->flags = p->property = 0;
        set_page_ref(p, 0);//清空引用
    }
    base->property = n;//说明连续有n个空闲块，属于空闲链表
    SetPageProperty(base);
    nr_free += n;//说明连续有n个空闲块，属于空闲链表
    list_add(&free_list, &(base->page_link));//
}
```

修改后的代码

```c
static void
default_init_memmap(struct Page *base, size_t n) { // base是这个头空闲页的指针，n是空闲页的数目
    assert(n > 0);
    struct Page *p = base;
    for (; p != base + n; p ++) {   // 不断递增进行初始化每个页表
        assert(PageReserved(p));    // 断言PG_reserved为0,表示这个页没有被保留
        p->flags = p->property = 0;
        set_page_ref(p, 0);         // 清空整个的链表中的页的引用为0
    }
    base->property = n;
    SetPageProperty(base);  // 只有头空闲块的flags-PG_property需要设置为1
    nr_free += n;
    list_add_before(&free_list, &(base->page_link));

    // 后面这两个不需要了，在循环中已经完成了base的
    //SetPageProperty(base);          // base的flag的PG_property也应该设置为1
    //list_add(&free_list, &(base->page_link)); // 将base的指针插入free_list这个struct中
}
```

### default_alloc_pages

在双向链表中寻找一个>=n的连续内存页，我们这里实现的首次匹配算法

```c
static struct Page *
default_alloc_pages(size_t n) {
    assert(n > 0);
    if (n > nr_free) {
        return NULL;
    }
    struct Page *page = NULL;
    list_entry_t *le = &free_list;
    while ((le = list_next(le)) != &free_list) {    // 找到大于n的节点
        struct Page *p = le2page(le, page_link);
        if (p->property >= n) {
            page = p;
            break;
        }
    }
    if (page != NULL) {
        if (page->property > n) {   // 如果大于n那么，截取前面的一部分
            struct Page *p = page + n;
            p->property = page->property - n;
            SetPageProperty(p);     // 设置这个p的flags-PG_property为1，因为已经是头空闲块了
            list_add_after(&(page->page_link), &(p->page_link));
        }
        list_del(&(page->page_link));
        nr_free -= n;
        ClearPageProperty(page);    // 清除为0
    }
    return page;
}
```

这里在详细描述下这个空闲链表的结构，他首先是一个双向的链表，对于每个节点，nr_free是这个节点的连续空闲页的数量，然后le2page这个宏能够根据节点的指针转换为Page结构，Page结构就是上述的那个，我们这里的default_alloc_pages函数就是寻找一个需要n个连续空闲页的位置，首先在双向链表中遍历，如果有个节点的连续空闲页的数量大于等于n的话（这个信息存储在这个节点的第一个Page结构中的property中），我们拿到头空闲页page，我们需要判断是否这个节点中的空闲页数量大于需要的n，如果大于那么将起分割，分割后的起始头空闲页为p，修改位信息后，将这个p页插到page这个页后面，删除page，最后记得更新这个节点剩下的空闲页的数量并且更新page页的位信息。

### default_free_pages

将想要free的n个页插回在双向链表中相应的位置，这里也是遍历双向链表的方法来寻找正确的位置

```c
static void
default_free_pages(struct Page *base, size_t n) {
    assert(n > 0);
    struct Page *p = base;
    for (; p != base + n; p ++) {
        assert(!PageReserved(p) && !PageProperty(p));   // 断言PG_reserved不是0,即这个是保留的，并且断言PG_property不是1，即已经分配了的
        p->flags = 0;
        set_page_ref(p, 0);
    }
    base->property = n;
    SetPageProperty(base);  // 设置base的flags的PG_property为1，表示是头空闲页并且是free的
    list_entry_t *le = list_next(&free_list);   // 从next开始遍历双向链表
    while (le != &free_list) {
        p = le2page(le, page_link); // 获取这个节点的头空闲页Page结构
        le = list_next(le); // le指向下一个
        if (base + base->property == p) {   // 如果base基址加上空闲块的数目正好是p，说明base向上合并
            base->property += p->property;
            ClearPageProperty(p);   // 清除p这个页面的flags的PG_property为0，因为它不是头页面
            list_del(&(p->page_link));
        } else if (p + p->property == base) {   // 如果是向下合并的话，同理
            p->property += base->property;
            ClearPageProperty(base);
            base = p;
            list_del(&(p->page_link));
        }
    }
    nr_free += n;   // 更新这个节点的nr_free的数量
    le = &free_list;
    while ((le = list_next(le)) != &free_list)  // 遍历双向链表，然后插入已经合并好的base
        if (base < le2page(le, page_link)) break;
    list_add_before(le, &base->page_link);
}
```

最后make qemu会显示check_alloc_page() succeeded!

## Part2 实现寻找虚拟地址对应的页表项　

在有页映射机制中，ucore采用了二级页表的机制，即一个一级的页目录，一个的二级的页表，然后我们看一个线性地址的结构32位，其中高10位为页目录项的索引，中10位为页表项的索引，低十二位为物理地址的偏移，其中页目录的地址是存储在一个cr3寄存器的。

![](http://image.bdwms.com/FlwVbp0WSBs5kF1kJl8deSjQEJVR)

再看下ucore中的la的结构定义

```c
// A linear address 'la' has a three-part structure as follows:
//
// +--------10------+-------10-------+---------12----------+
// | Page Directory |   Page Table   | Offset within Page  |
// |      Index     |     Index      |                     |
// +----------------+----------------+---------------------+
//  \--- PDX(la) --/ \--- PTX(la) --/ \---- PGOFF(la) ----/
//  \----------- PPN(la) -----------/
//
// The PDX, PTX, PGOFF, and PPN macros decompose linear addresses as shown.
// To construct a linear address la from PDX(la), PTX(la), and PGOFF(la),
// use PGADDR(PDX(la), PTX(la), PGOFF(la)).
```

get_pte主要就是由页目录，一个la(线性地址)，是否创建create作为输入，首先根据输入的pgdir和la获得页表的地址，然后看PTE_P位是否设置，没有设置说明没有创建相对应的二级页表，再根据create参数来表名是否需要创建二级页表，获取物理页，设置引用，清空，设置PTE，最后利用PTX(la)获取中10位，加上我们获得页表项地址拿到物理地址，KADDR根据物理地址获取相对应的虚拟页地址

 ```c
//get_pte - get pte and return the kernel virtual address of this pte for la
//        - if the PT contians this pte didn't exist, alloc a page for PT
// parameter:
//  pgdir:  the kernel virtual base address of PDT
//  la:     the linear address need to map
//  create: a logical value to decide if alloc a page for PT
// return vaule: the kernel virtual address of this pte
pte_t *
get_pte(pde_t *pgdir, uintptr_t la, bool create) {
    /* LAB2 EXERCISE 2: YOUR CODE
     *
     * If you need to visit a physical address, please use KADDR()
     * please read pmm.h for useful macros
     *
     * Maybe you want help comment, BELOW comments can help you finish the code
     *
     * Some Useful MACROs and DEFINEs, you can use them in below implementation.
     * MACROs or Functions:
     *   PDX(la) = the index of page directory entry of VIRTUAL ADDRESS la.
     *   KADDR(pa) : takes a physical address and returns the corresponding kernel virtual address.
     *   set_page_ref(page,1) : means the page be referenced by one time
     *   page2pa(page): get the physical address of memory which this (struct Page *) page  manages
     *   struct Page * alloc_page() : allocation a page
     *   memset(void *s, char c, size_t n) : sets the first n bytes of the memory area pointed by s
     *                                       to the specified value c.
     * DEFINEs:
     *   PTE_P           0x001                   // page table/directory entry flags bit : Present
     *   PTE_W           0x002                   // page table/directory entry flags bit : Writeable
     *   PTE_U           0x004                   // page table/directory entry flags bit : User can access
     */
#if 0
    pde_t *pdep = NULL;   // (1) find page directory entry
    if (0) {              // (2) check if entry is not present
                          // (3) check if creating is needed, then alloc page for page table
                          // CAUTION: this page is used for page table, not for common data page
                          // (4) set page reference
        uintptr_t pa = 0; // (5) get linear address of page
                          // (6) clear page content using memset
                          // (7) set page directory entry's permission
    }
    return NULL;          // (8) return page table entry
#endif
    pde_t *pdep = &pgdir[PDX(la)];  // 尝试获取页表，pgdir是一级页表本身,PDX(la)获取一级页表项的索引，就是高10位
    if ((*pdep & PTE_P) == 0) {     // 如果没有设置PTE_P位的话
        if (!create) return NULL;   // 如果create为0不创建二级页表直接返回
        struct Page *page = alloc_page();   // 否则申请一个物理页
        if (page == NULL) return NULL;  // 申请失败了就返回
        set_page_ref(page, 1);  // 成功的话，这个物理页的引用+1
        uintptr_t pa = page2pa(page);   // 获取这个物理页的线性地址
        memset(KADDR(pa), 0, PGSIZE);   // 清除这个页面的n个字节
        *pdep = pa | PTE_U | PTE_W | PTE_P;  // 设置页目录控制位
    }
    pte_t *pa = (pte_t *)PTE_ADDR(*pdep) + PTX(la); // 返回页的物理地址，我们找到的二级也白哦的入口，加上PTX(la)返回虚拟地址la的页表项索引就是中间10位
    return KADDR((uintptr_t)pa);    // KADDR输入物理地址进行转换，得到的就是页表项入口地址
}
 ```

然后我们完成练习三再make qemu的会有check_pgdir() succeeded!输出

## Part3 释放某虚地址所在的页并取消对应二级页表项的映射

```c
//page_remove_pte - free an Page sturct which is related linear address la
//                - and clean(invalidate) pte which is related linear address la
//note: PT is changed, so the TLB need to be invalidate 
static inline void
page_remove_pte(pde_t *pgdir, uintptr_t la, pte_t *ptep) {
    /* LAB2 EXERCISE 3: YOUR CODE
     *
     * Please check if ptep is valid, and tlb must be manually updated if mapping is updated
     *
     * Maybe you want help comment, BELOW comments can help you finish the code
     *
     * Some Useful MACROs and DEFINEs, you can use them in below implementation.
     * MACROs or Functions:
     *   struct Page *page pte2page(*ptep): get the according page from the value of a ptep
     *   free_page : free a page
     *   page_ref_dec(page) : decrease page->ref. NOTICE: ff page->ref == 0 , then this page should be free.
     *   tlb_invalidate(pde_t *pgdir, uintptr_t la) : Invalidate a TLB entry, but only if the page tables being
     *                        edited are the ones currently in use by the processor.
     * DEFINEs:
     *   PTE_P           0x001                   // page table/directory entry flags bit : Present
     */
#if 0
    if (0) {                      //(1) check if this page table entry is present
        struct Page *page = NULL; //(2) find corresponding page to pte
                                  //(3) decrease page reference
                                  //(4) and free this page when page reference reachs 0
                                  //(5) clear second page table entry
                                  //(6) flush tlb
    }
#endif
    if (*ptep & PTE_P) {    // 判断这个页表中的页表项是否存在
        struct Page *page = pte2page(*ptep);    // 从这个页表项获取相对的页表
        if (page_ref_dec(page) == 0) {  // 如果这个页表只被引用了一次那么直接释放这个页表
            free_page(page);
        }
        *ptep = 0;  //　释放二级页表中这个页表项
        tlb_invalidate(pgdir, la);  //　更新页表
    }
}
```

page_remove_pte输入为页表的地址，la线性地址，需要释放的页表项，整个过程注释写很清楚，最后makee qemu看到断言都过了，然后ucore基于我们的段页式完成了lab1中的时钟中断。

![](http://image.bdwms.com/Fth1qTkWBQOKBQFCnBl1F-5khykP)

# 总结

比预期晚了两天才完成。。。还是需要调整速度和方法，我太菜了，回头再把源码好好看看。