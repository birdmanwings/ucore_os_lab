# 前言

回头好好打基础，这次准备写写清华的ucore实验，废话不多说，先是lab1，代码还有相关的笔记资料放在[github](https://github.com/birdmanwings/ucore_os_lab)，都在study_notes文件下

# 正文

## Part1

1. 操作系统镜像文件ucore.img是如何一步一步生成的？(需要比较详细地解释Makefile中每一条相关命令和命令参数的含义，以及说明命令导致的结果)
2. 一个被系统认为是符合规范的硬盘主引导扇区的特征是什么？



1. 首先我们大概分析一下Makefile中的主要代码，能够发现在207行看到.DEFAULT_GOAL这个默认目标文件是205定义的TARGETS，但是在Makefile中并没有TARGETS的定义，然后我上网翻了翻，原来是在tools/function.mk中由do_create_target宏中更改，再有create_target来进行调用，create_target函数根据载入的参数不同来返回相应的模板。所以在Makefile中调用一次create_target就会给TARGETS添加一个目标。最终生成了bin目录下的四个文件：bootblock,kernel,sign,ucore.img。

   178到186行：

   ```makefile
   # create ucore.img
   UCOREIMG	:= $(call totarget,ucore.img)
   
   $(UCOREIMG): $(kernel) $(bootblock)
   	$(V)dd if=/dev/zero of=$@ count=10000
   	$(V)dd if=$(bootblock) of=$@ conv=notrunc
   	$(V)dd if=$(kernel) of=$@ seek=1 conv=notrunc
   
   $(call create_target,ucore.img)
   ```

   看到ucore.img是由kernel和bootblock生成，dd命令将起组装

   来看kernel是怎么生成的，143到149行

   ```makefile
   $(kernel): tools/kernel.ld
   
   $(kernel): $(KOBJS)
   	@echo + ld $@
   	$(V)$(LD) $(LDFLAGS) -T tools/kernel.ld -o $@ $(KOBJS)
   	@$(OBJDUMP) -S $@ > $(call asmfile,kernel)
   	@$(OBJDUMP) -t $@ | $(SED) '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(call symfile,kernel)
   
   ```

   依赖tools/kernel.ld文件对起进行编译，然后Makefile太复杂了，我们直接看他的输出，前面的一些gcc的是他编译具体文件的指令，然后看这个ld指令

   ```
   + ld bin/kernel
   ld -m    elf_i386 -nostdlib -T tools/kernel.ld -o bin/kernel  obj/kern/init/init.o obj/kern/libs/stdio.o obj/kern/libs/readline.o obj/kern/debug/panic.o obj/kern/debug/kdebug.o obj/kern/debug/kmonitor.o obj/kern/driver/clock.o obj/kern/driver/console.o obj/kern/driver/picirq.o obj/kern/driver/intr.o obj/kern/trap/trap.o obj/kern/trap/vectors.o obj/kern/trap/trapentry.o obj/kern/mm/pmm.o  obj/libs/string.o obj/libs/printfmt.o
   ```

   > -T <scriptfile>  让连接器使用指定的脚本

   ld链接了.o的文件生成了bin/kernel文件，具体的.o文件就是上面显示的这些。

   然后看bootblock是怎么生成的，159到166行：

   ```makefile
   bootblock = $(call totarget,bootblock)
   
   $(bootblock): $(call toobj,$(bootfiles)) | $(call totarget,sign)
   	@echo + ld $@
   	$(V)$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 $^ -o $(call toobj,bootblock)
   	@$(OBJDUMP) -S $(call objfile,bootblock) > $(call asmfile,bootblock)
   	@$(OBJCOPY) -S -O binary $(call objfile,bootblock) $(call outfile,bootblock)
   	@$(call totarget,sign) $(call outfile,bootblock) $(bootblock)
   ```

   然后看输出bootblock.o生成需要依赖bootasm.o, bootmain.o文件，然后还有一个sign来进行签名

   ```
   + ld bin/bootblock
   ld -m    elf_i386 -nostdlib -N -e start -Ttext 0x7C00 obj/boot/bootasm.o obj/boot/bootmain.o -o obj/bootblock.o
   ```

   ld相关的参数

   > -m <emulation>  模拟为i386上的连接器
   > -nostdlib  不使用标准库
   > -N  设置代码段和数据段均可读写
   > -e <entry>  指定入口
   > -Ttext  制定代码段开始位置

   打印出来的命令

   ```
   + cc boot/bootasm.S
   gcc -Iboot/ -march=i686 -fno-builtin -fno-PIC -Wall -ggdb -m32 -gstabs -nostdinc  -fno-stack-protector -Ilibs/ -Os -nostdinc -c boot/bootasm.S -o obj/boot/bootasm.o
   + cc boot/bootmain.c
   gcc -Iboot/ -march=i686 -fno-builtin -fno-PIC -Wall -ggdb -m32 -gstabs -nostdinc  -fno-stack-protector -Ilibs/ -Os -nostdinc -c boot/bootmain.c -o obj/boot/bootmain.o
   ```

   gcc相关的参数，直接翻网上的

   > -ggdb  生成可供gdb使用的调试信息。这样才能用qemu+gdb来调试bootloader or ucore。
   > -m32  生成适用于32位环境的代码。我们用的模拟硬件是32bit的80386，所以ucore也要是32位的软件。
   > -gstabs  生成stabs格式的调试信息。这样要ucore的monitor可以显示出便于开发者阅读的函数调用栈信息
   > -nostdinc  不使用标准库。标准库是给应用程序用的，我们是编译ucore内核，OS内核是提供服务的，所以所有的服务要自给自足。
   > -fno-stack-protector  不生成用于检测缓冲区溢出的代码。这是for 应用程序的，我们是编译内核，ucore内核好像还用不到此功能。
   > -Os  为减小代码大小而进行优化。根据硬件spec，主引导扇区只有512字节，我们写的简单bootloader的最终大小不能大于510字节。
   > -I<dir>  添加搜索头文件的路径 
   >
   > -fno-builtin  除非用`_builtin_`前缀，否则不进行`_builtin_`函数的优化

   然后是生成sign的命令：

   ```makefile
   $(call add_files_host,tools/sign.c,sign,sign)
   $(call create_target_host,sign,sign)
   ```

   打印出来的命令

   ```
   + cc tools/sign.c
   gcc -Itools/ -g -Wall -O2 -c tools/sign.c -o obj/sign/tools/sign.o
   gcc -g -Wall -O2 obj/sign/tools/sign.o -o bin/sign
   ```

   在结果里面没有打印出来sign是如何处理bootblock的，那我们只能从Makefile中来看

   ```makefile
   @$(OBJCOPY) -S -O binary $(call objfile,bootblock) $(call outfile,bootblock)
   ```

   答案给的命令打印出来是`objcopy -S -O binary obj/bootblock.o obj/bootblock.out`意思是拷贝二进制代码bootblock.o到.out文件中，然后是这个makefile命令

   ```makefile
   @$(call totarget,sign) $(call outfile,bootblock) $(bootblock)
   ```

   `bin/sign obj/bootblock.out bin/bootblock`使用sign处理

   这里的sign的功能是通过编译执行一个预先写好的 tools/sign.c 文件，读取整个 obj/bootblock.out ，判断文件大小是不是小于等于 510 ，如果不是说明构建失败，退出。如果成功则填充 magic number 0xAA55 ，输出到 bin/bootblock 中。

   最后的将kernel和bootblock导入ucore.img中

   生成一个有10000个块的文件，每个块默认512字节，用0填充

   ```
   dd if=/dev/zero of=bin/ucore.img count=10000
   ```

   把bootblock中的内容写到第一个块

   ```
   dd if=/dev/zero of=bin/ucore.img count=10000
   ```

   从第二个块开始写kernel中的内容

   ```
   dd if=bin/kernel of=bin/ucore.img seek=1 conv=notrunc
   ```

   dd命令的相关参数（dd命令用于读取、转换并输出数据。）

> `if` ： input file 。
>
> `of` ： output file 。
>
> `count` ：读取并写入的 block size 数。
>
> `bs` ： block size ，默认 512 。
>
> `seek` ：跳过写入文件的 block size 数。
>
> `conv` ： conv 符号处理的东西有点多，就这里的 `notrunc` 是不设置 `write`syscall 的参数 `O_TRUNC` （ `dd` 默认会设置），这就使得 `dd` 输出的文件已存在时，如果现在输出的比原来的要小，则文件大小保持被 `dd` 之前一样不变。

1. 磁盘主引导扇区只有512字节,磁盘最后两个字节为`0x55AA`, 由不超过466字节的启动代码和不超过64字节的硬盘分区表加上两个字节的结束符组成

## Part2

1. 从CPU加电后执行的第一条指令开始，单步跟踪BIOS的执行。
2. 在初始化位置0x7c00设置实地址断点,测试断点正常。
3. 从0x7c00开始跟踪代码运行,将单步跟踪反汇编得到的代码与bootasm.S和 bootblock.asm进行比较。
4. 自己找一个bootloader或内核中的代码位置，设置断点并进行测试。



1. 更改tools/gdbinit的内容设置为

   ```
   set architecture i8086
   target remote :1234
   ```

   然后在lab1的目录下make debug

   ![](http://image.bdwms.com/FiQv3rdiyYA4xUO76OlAOyxTQT1G)

   si单步调试

    x /2i $pc  //显示当前eip处的汇编指令

2. 然后打断点在0x7c00处，c是continue的意思

   ```
   b *0x7c00
   c
   ```

   然后查看指令x /5i $pc

   ![](http://image.bdwms.com/FolYHC56wXLfnjRSHoYFH-kWO_T1)

   能够看到打出来的汇编和我们的bootblock中的汇编代码是一样的

   ![](http://image.bdwms.com/FsrQMwsJhQVcOuGcai9pKILi1H-x)

## Part3

BIOS将通过读取硬盘主引导扇区到内存，并转跳到对应内存中的位置执行bootloader。请分析bootloader是如何完成从实模式进入保护模式的。

- 为何开启A20，以及如何开启A20
- 如何初始化GDT表
- 如何使能和进入保护模式

1. 为了兼容。8086只有20根总线，但是“段：偏移”寻址方式（段*4+偏移，段和偏移寄存器都是16位，所以最大为FFFF0+FFFF=10FFEF）支持的地址略高于2^20，当高于0x100000时，需要取模进行回卷，但是80286有了24根总线寻址范围为16MB，所以为了兼容，当A20总线关闭保持回卷，否则禁用回卷可以直接访问高位

2. 这里直接贴[叶姐姐](https://xr1s.me/2018/05/15/ucore-lab1-report/#Question_2-2)的吧...GDT表太麻烦了，在bootblock.s中是建立了格式并初始化

   ```
   # Bootstrap GDT
   .p2align 2                                          # force 4 byte alignment
   gdt:
       SEG_NULLASM                                     # null seg
       SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # code seg for bootloader and kernel
       SEG_ASM(STA_W, 0x0, 0xffffffff)                 # data seg for bootloader and kernel
   
   gdtdesc:
       .word 0x17                                      # sizeof(gdt) - 1
       .long gdt                                       # address gdt
   ```

3. 有一个cr0寄存器置为1时，就进入保护模式

最后整个bootblock.s的代码分析在lab3/bootblocks_analysis.md文件中

## Part4

通过阅读bootmain.c，了解bootloader如何加载ELF文件。通过分析源代码和通过qemu来运行并调试bootloader&OS，

- bootloader如何读取硬盘扇区的？
- bootloader是如何加载ELF格式的OS？

1. 主要看bootmain主函数，一步一步进行分析，首先是读取第一个扇区，然后判断ELF头，然后是加载之后的扇区，最后是利用强制转换根据ELF头中的信息找到内核的入口来调用函数，具体的分析在bootblockc_analysis.md文件中
2. 在libs/elf.h文件中定义了ELF头的信息，通过检查一个magic number判断，最后根据ELF文件头中的的信息跳转到e_entry，即内核的指定入口

## Part5

主要就是程序堆栈那些东西，以前上什么破网安课的时候都说烂了，从高到低增长，函数参数从右到左压栈，压返回地址eip，压当前的ebp，最后是函数中的局部变量压入栈

![](http://image.bdwms.com/FqsbJjCT1jJuDfFU2qsK_zYxV8aM) 

然后根据注释我们可以写代码了

```c
void
print_stackframe(void) {
    /* LAB1 YOUR CODE : STEP 1 */
    /* (1) call read_ebp() to get the value of ebp. the type is (uint32_t);
     * (2) call read_eip() to get the value of eip. the type is (uint32_t);
     * (3) from 0 .. STACKFRAME_DEPTH
     *    (3.1) printf value of ebp, eip
     *    (3.2) (uint32_t)calling arguments [0..4] = the contents in address (uint32_t)ebp +2 [0..4]
     *    (3.3) cprintf("\n");
     *    (3.4) call print_debuginfo(eip-1) to print the C calling function name and line number, etc.
     *    (3.5) popup a calling stackframe
     *           NOTICE: the calling funciton's return addr eip  = ss:[ebp+4]
     *                   the calling funciton's ebp = ss:[ebp]
     */

    uint32_t ebp = read_ebp();
    uint32_t eip = read_eip();

    int i, j;
    for (i = 0; i < STACKFRAME_DEPTH && ebp != 0; i++) {
        cprintf("ebp:0x%08x eip:0x%08x args:", ebp, eip);
        uint32_t *args = (uint32_t *)ebp + 2;
        for (j = 0; j < 4; j++) {
            cprintf("0x%08x ", args[j]);
        }
        cprintf("\n");
        print_debuginfo(eip - 1);
        eip = ((uint32_t *)ebp)[1];
        ebp = ((uint32_t *)ebp)[0];
    }
}
```

make qemu后打印结果

![](http://image.bdwms.com/Fl_naslWD0oXt9JvAp8DMnm1A1s2)

最后一行的unknow翻一下obj/bootblock.asm，查一下7d71

![](http://image.bdwms.com/Ftpoiut_QL32T-JvV-ROt1ImgM1V)

然后看一下应该就是指最初进入kernel的地址

## Part6

1. 中断描述符表（也可简称为保护模式下的中断向量表）中一个表项占多少字节？其中哪几位代表中断处理代码的入口？
2. 请编程完善kern/trap/trap.c中对中断向量表进行初始化的函数idt_init。在idt_init函数中，依次对所有中断入口进行初始化。使用mmu.h中的SETGATE宏，填充idt数组内容。每个中断的入口由tools/vectors.c生成，使用trap.c中声明的vectors数组即可。
3. 请编程完善trap.c中的中断处理函数trap，在对时钟中断进行处理的部分填写trap函数中处理时钟中断的部分，使操作系统每遇到100次时钟中断后，调用print_ticks子程序，向屏幕上打印一行文字”100 ticks”。



1. 8个字节，offset为32位，0-15为低16位，48-63为高16位，两段组成偏移量，16-31为段选择子得到段基址，加上前面的段偏移量就可以得到中断处理代码的入口。

2. 根据题目注释写

   ```c
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
       extern uintptr_t __vectors[];  //声明__vectors[]
       int i;
       for (i = 0; i < 256; i++) {
           SETGATE(idt[i], 0, GD_KTEXT, __vectors[i], DPL_KERNEL); //填充中断向量表
       }
       SETGATE(idt[T_SWITCH_TOK], 0, GD_KTEXT, __vectors[T_SWITCH_TOK], DPL_USER); //设置从用户态到内核态，注意这里的权限为DPL_USER
       lidt(&idt_pd);  //加载中断向量表到寄存器中
   }
   ```

   先是初始化中断向量表，然后循环填充，SETGATE宏，其中五个参数的意思是

   - 中断描述符表
   - 判断是中断还是trap，这里都是中断直接0
   - 段选择器，看下memlayout.h中定义的，一般是选择内核代码段，直接用他定义的宏
   - 表示偏移，就是__vectors中对应的值
   - 权限，这里除了用户态转内核态权限是User其他中断都应该是内核态权限

   然后设置用户态到内核态的（这里我没看到注释描述。。。直接看了下answer添加了一个），最后调用lidt指定将中断向量表加载到指定的寄存器中。

3. 很简单不多叙述了

   ```c
   ticks++;
   if (ticks % TICK_NUM == 0) {
      print_ticks();
   }
   ```
   最后的输出make qemu

   ![](http://image.bdwms.com/FoSkmHYZzGQKkpvJeR3smzF7GhPo)

# 总结

lab1还是主要熟悉下基本的操作，继续学习了，边社畜边做lab好慢啊。