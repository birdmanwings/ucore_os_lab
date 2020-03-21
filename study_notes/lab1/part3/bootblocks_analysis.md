```
#include <inc/mmu.h>		// mmu.h 内含有需要使用的宏定义与函数
 
# Start the CPU: switch to 32-bit protected mode, jump into C.		// 这些代码的作用为转换到 32 位保护模式，然后跳转到 main.c
# The BIOS loads this code from the first sector of the hard disk into		// BIOS 读取硬盘第一扇区的内容到 0x7c00
# memory at physical address 0x7c00 and starts executing in real mode		// 设置 CS、IP 寄存器，执行实模式
# with %cs=0 %ip=7c00.
 
.set PROT_MODE_CSEG, 0x8         # kernel code segment selector		// 内核代码段 selector，用于寻找 GDT 条目
.set PROT_MODE_DSEG, 0x10        # kernel data segment selector		// 内核数据段 selector，用于寻找 GDT 条目
.set CR0_PE_ON,      0x1         # protected mode enable flag		// 用于设置 CR0 的 PE 位，目的为开启保护模式
 
.globl start		// 设置全局符号 start
start:
  .code16                     # Assemble for 16-bit mode		// 16位指令
  cli                         # Disable interrupts		// 屏蔽中断，Bootloader 执行过程中不响应中断
  cld                         # String operations increment		// 从低地址到高地址
 
  # Set up the important data segment registers (DS, ES, SS).		// 初始化段寄存器为0
  xorw    %ax,%ax             # Segment number zero
  movw    %ax,%ds             # -> Data Segment		// 数据段寄存器
  movw    %ax,%es             # -> Extra Segment		// 附加段寄存器
  movw    %ax,%ss             # -> Stack Segment		// 栈段寄存器
```
对于下面的汇编，第 6 行，inb 指令的意思是从 I/O 读取 1byte 的数据，存入 al 寄存器中，而读取 0x64 端口可以从表中看出意思是读取状态寄存器的值
第 7 行，testb 指令的意思是对两个操作数执行逻辑 AND 并设置 flags 寄存器，在这里也就是读取 al 寄存器中的数据的第二位是否为 0
第 8 行，jnz 指令的意思是如果不是 0 则跳转到 seta20.1，从表中可以看出，如果第二位为 0 代表输入缓存为空，即可以向端口 0x60 或者 0x64 写数据
第 9 、10 行，outb 指令的意思是向 I/O 写入 1byte 的数据，也就是向命令寄存器写入 0xD1，即命令 PS/2 Controller 将下一个写入 0x60 的字节写出到 Output Port
第 16 行，将 0xdf 写入 0x60，即将 Output Port 的第二位设置为 1
至此，就打开了 A20 gate

```
# Enable A20:
  #   For backwards compatibility with the earliest PCs, physical
  #   address line 20 is tied low, so that addresses higher than
  #   1MB wrap around to zero by default.  This code undoes this.
seta20.1:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.1
  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64
 
seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.2
  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60
```

其中对应的IO端口的相关表格

PS/2 Controller IO Ports：

| IO Port | Access Type | Purpose          |
| ------- | ----------- | ---------------- |
| 0x60    | Read/Write  | Data Port        |
| 0x64    | Read        | Status Register  |
| 0x64    | Write       | Command Register |

Status Register

| Bit  | Meaning                                                      |
| ---- | ------------------------------------------------------------ |
| 1    | Input buffer status (0 = empty, 1 = full)(must be clear before attempting to write data to IO port 0x60 or IO port 0x64) |

PS/2 Controller Commands

| **Command Byte** | **Meaning**                                                  | **Response Byte** |
| ---------------- | ------------------------------------------------------------ | ----------------- |
| 0xD1             | Write next byte to Controller Output PortNote: Check if output buffer is empty first | None              |

如果有一个“next byte”，那么在确保控制器准备好之后(通过确保状态寄存器的第1位是清除的)，需要将下一个字节写到IO端口0x60。

PS/2 Controller Output Port

| Bit  | Meaning           |
| ---- | ----------------- |
| 1    | A20 gate (output) |

加载GDT表

```
lgdt gdtdesc #将全局描述符表描述符加载到全局描述符表寄存器  
```

进入保护模式，前面预定义了$CR0_PE_ON为1，或操作后为1打开保护模式

```
cr0中的第0位为1表示处于保护模式  
cr0中的第0位为0，表示处于实模式  
把控制寄存器cr0加载到eax中  


movl %cr0, %eax
orl $CR0_PE_ON, %eax
movl %eax, %cr0
```

长跳转更新cs

```
ljmp $PROT_MODE_CSEG, $protcseg
.code32
protcseg:
```

设置段寄存器，并建立堆栈

```
movw $PROT_MODE_DSEG, %ax
movw %ax, %ds
movw %ax, %es
movw %ax, %fs
movw %ax, %gs
movw %ax, %ss
movl $0x0, %ebp
movl $start, %esp
```

转换完成，进入boot主方法

```
call bootmain
```

