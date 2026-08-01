#已经编译过的内核源码路径
KERNEL_DIR = /home/uisrc/rk3576/rk3576linux_6.10_250214/kernel

#获取当前路径
CURRENT_DIR = $(shell pwd)

APP = key_control

all : 
#进入并调用内核源码目录中Makefile的规则, 将当前的目录中的源码编译成模块
	make -C $(KERNEL_DIR) M=$(CURRENT_DIR) modules 
	rm -rf *.symvers *.order *.o *.mod.o *.mod.c

ifneq ($(APP), )
	$(CROSS_COMPILE)gcc $(APP).c -o $(APP)
endif

clean : 
	make -C $(KERNEL_DIR) M=$(CURRENT_DIR) clean
	rm $(APP)


