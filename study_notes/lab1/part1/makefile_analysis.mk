#makefile中109-117
# include kernel/user
INCLUDE += libs/
CFLAGS  += $(addprefix -I,$(INCLUDE))
LIBDIR  += libs
$(call add_files_cc,$(call listf_cc,$(LIBDIR)),libs,)

#此段的含义就是把内核目录代码中所有的libs/*c,的文件进行编译，最后把编译后的目标文件完整路径名保存在__temp__packet变量中，
#并且生成目标文件新目录路径应该为obj/libs/*.o,*.d

#源代码的120-153
# kernel

KINCLUDE    += kern/debug/ \
               kern/driver/ \
               kern/trap/ \
               kern/mm/

KSRCDIR     += kern/init \
               kern/libs \
               kern/debug \
               kern/driver \
               kern/trap \
               kern/mm

KCFLAGS     += $(addprefix -I,$(KINCLUDE))

#该句同上，只是目录变为了$（KSRCDIR),编译所有内核文件
#最踪生成的路径应该obj/kern/init/*.o... 并追加保存路径在__temp__packet中。
$(call add_files_cc,$(call listf_cc,$(KSRCDIR)),kernel,$(KCFLAGS))

#应为所有的编译后的目标文件路径都保存在__temp_packet中，则该函数直接引用，用来最后的链接工作
KOBJS   = $(call read_packet,kernel libs)

# create kernel target
#最总的目标文件obj/kernel
kernel = $(call totarget,kernel)

$(kernel): tools/kernel.ld
#最总的目标文件的规则
$(kernel): $(KOBJS)
    @echo + ld $@
    #链接obj/libs/*和obj/kernel/init/*...所有的目标文件生成elf-i386的内核文件,并且使用kernel.ld链接器脚本
    $(V)$(LD) $(LDFLAGS) -T tools/kernel.ld -o $@ $(KOBJS)
    #最终的内核文件应该去除符号表等信息，并输出符号表信息，汇编文件信息，和输出信息
    @$(OBJDUMP) -S $@ > $(call asmfile,kernel)
    @$(OBJDUMP) -t $@ | $(SED) '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(call symfile,kernel)



# create bootblock
#启动扇区的编译，过程与内核差不多唯一的区别是需要对编译后的启动扇区进行签名，即有效启动扇区，最后字节为0x55aa。
bootfiles = $(call listf_cc,boot)
$(foreach f,$(bootfiles),$(call cc_compile,$(f),$(CC),$(CFLAGS) -Os -nostdinc))

bootblock = $(call totarget,bootblock)

$(bootblock): $(call toobj,$(bootfiles)) | $(call totarget,sign)
    @echo + ld $@
    $(V)$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 $^ -o $(call toobj,bootblock)
    @$(OBJDUMP) -S $(call objfile,bootblock) > $(call asmfile,bootblock)
    @$(OBJCOPY) -S -O binary $(call objfile,bootblock) $(call outfile,bootblock)
    @$(call totarget,sign) $(call outfile,bootblock) $(bootblock)

$(call create_target,bootblock)


# create 'sign' tools
#在内核工具目录中,sign.c，用来给扇区签名的小工具,为什么这而使用host呢，
#是因为该工具是在特定操作系统下的工具，所以编译过程跟内核编译过程完全不同，最显著的就是nostdlibc内核是必须的编译选项，
#而应用软件一般都是依赖C库，并且内核代码为了精简，也没有栈溢出保护 --no-stack-protector
$(call add_files_host,tools/sign.c,sign,sign)
$(call create_target_host,sign,sign)


#最后把编译出的二进制文件和bootloader都写进一个大文件中，用来模拟硬盘。使用linux下dd块命令
UCOREIMG    := $(call totarget,ucore.img)

$(UCOREIMG): $(kernel) $(bootblock)
    $(V)dd if=/dev/zero of=$@ count=10000
    $(V)dd if=$(bootblock) of=$@ conv=notrunc
    $(V)dd if=$(kernel) of=$@ seek=1 conv=notrunc

$(call create_target,ucore.img)