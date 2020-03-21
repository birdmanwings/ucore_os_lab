BJPREFIX    := __objs_

.SECONDEXPANSION:
# -------------------- function begin --------------------

# list all files in some directories: (#directories, #types)
#返回相应directories目录下所有 类型为（types）的文件
#example 输入为listf(libs, c s),输出为libs/a.c libs/a.s
listf = $(filter $(if $(2),$(addprefix %.,$(2)),%),\
          $(wildcard $(addsuffix $(SLASH)*,$(1))))

# get .o obj files: (#files[, packet])
# 给出文件名列表files,和软件包名称packet，返回相应文件的目标文件名称
#example $(call toobj,libs/a.c libs/b.c,__obj_),生成相应的输出makefile代码为 obj/__obj_/libs/a.o obj/__obj_/libs/b.o
toobj = $(addprefix $(OBJDIR)$(SLASH)$(if $(2),$(2)$(SLASH)),$(addsuffix .o,$(basename $(1))))

# get .d dependency files: (#files[, packet])
#输入为文件名列表，输出为相应代码文件的依赖文件名列表
#example $(call todep,libs/a.c libs/b.c,__obj__),对应相应的makefile代码为 __obj_/libs/a.d __obj_/libs/b.d
todep = $(patsubst %.o,%.d,$(call toobj,$(1),$(2)))

#输出最总的目标文件完整路径名，
#example $(call totarget,kernel)，则对应于makefile代码为输出的最总内核目标文件为bin/kernel
totarget = $(addprefix $(BINDIR)$(SLASH),$(1))

# change $(name) to $(OBJPREFIX)$(name): (#names)
#给定名字加上前缀$(OBJPREFIX)
packetname = $(if $(1),$(addprefix $(OBJPREFIX),$(1)),$(OBJPREFIX))

# cc compile template, generate rule for dep, obj: (file, cc[, flags, dir])
#内核各个模块编译的C代码模板，迎来为每一个.c或者.s文件生成编译后的目标文件
define cc_template
#生成依目标文件的依赖文件。4个$$$$符号是因为该代码要被eval两次，并且最终生成的makefile文件继续保留对规则目标文件名的引用
$$(call todep,$(1),$(4)): $(1) | $$$$(dir $$$$@)
	@$(2) -I$$(dir $(1)) $(3) -MM $$< -MT "$$(patsubst %.d,%.o,$$@) $$@"> $$@

#该模板就是生成目标文件的规则，
$$(call toobj,$(1),$(4)): $(1) | $$$$(dir $$$$@)
	@echo + cc $$<
    $(V)$(2) -I$$(dir $(1)) $(3) -c $$< -o $$@
#用ALLOBJS保存所有的目标文件
ALLOBJS += $$(call toobj,$(1),$(4))
endef

# compile file: (#files, cc[, flags, dir])
#用来生成最总的makefile中的所有目标文件的规则。
define do_cc_compile
$$(foreach f,$(1),$$(eval $$(call cc_template,$$(f),$(2),$(3),$(4))))
endef

# add files to packet: (#files, cc[, flags, packet, dir])
#此模板，就是真正在makefile中用来编译所有的目表文件，并生成makefile规则的模板。
define do_add_files_to_packet
#__temp_packet__用来记录所有的临时目标文件。
__temp_packet__ := $(call packetname,$(4))
ifeq ($$(origin $$(__temp_packet__)),undefined)
$$(__temp_packet__) :=
endif
__temp_objs__ := $(call toobj,$(1),$(5))
$$(foreach f,$(1),$$(eval $$(call cc_template,$$(f),$(2),$(3),$(5))))
$$(__temp_packet__) += $$(__temp_objs__)
endef

# add objs to packet: (#objs, packet)
define do_add_objs_to_packet
__temp_packet__ := $(call packetname,$(2))

ifeq ($$(origin $$(__temp_packet__)),undefined)
$$(__temp_packet__) :=
endif
$$(__temp_packet__) += $(1)
endef

# add packets and objs to target (target, #packes, #objs[, cc, flags])
# 用来生成最终的target，在内核代码中，也就是最终的kernel和bootloader的makefile规则，
# $$(__temp_objs__) | $$$$(dir $$$$@) 该语句表示依赖规则的目标文件，还需要有目录的支持，如果目录不存在则应该创建，见后面规则。
define do_create_target
__temp_target__ = $(call totarget,$(1))
__temp_objs__ = $$(foreach p,$(call packetname,$(2)),$$($$(p))) $(3)
TARGETS += $$(__temp_target__)
ifneq ($(4),)
$$(__temp_target__): $$(__temp_objs__) | $$$$(dir $$$$@)
	$(V)$(4) $(5) $$^ -o $$@
else
$$(__temp_target__): $$(__temp_objs__) | $$$$(dir $$$$@)
endif
endef

# finish all
define do_finish_all
ALLDEPS = $$(ALLOBJS:.o=.d)
$$(sort $$(dir $$(ALLOBJS)) $(BINDIR)$(SLASH)
# 如果相应目录不存在则执行makedir -p 命令
$(OBJDIR)$(SLASH)):
    @$(MKDIR) $$@
endef

# --------------------  function end  --------------------
# compile file: (#files, cc[, flags, dir])
cc_compile = $(eval $(call do_cc_compile,$(1),$(2),$(3),$(4)))

# add files to packet: (#files, cc[, flags, packet, dir])
add_files = $(eval $(call do_add_files_to_packet,$(1),$(2),$(3),$(4),$(5)))

# add objs to packet: (#objs, packet)
add_objs = $(eval $(call do_add_objs_to_packet,$(1),$(2)))

# add packets and objs to target (target, #packes, #objs, cc, [, flags])
create_target = $(eval $(call do_create_target,$(1),$(2),$(3),$(4),$(5)))

read_packet = $(foreach p,$(call packetname,$(1)),$($(p)))

add_dependency = $(eval $(1): $(2))

finish_all = $(eval $(call do_finish_all))
