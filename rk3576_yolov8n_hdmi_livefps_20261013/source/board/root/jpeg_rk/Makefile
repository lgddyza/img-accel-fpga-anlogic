KDIR ?= /lib/modules/$(shell uname -r)/build
SGDMA_DIR ?= /root/pcie_smoke_demo/vendor_deploy/sgdma_drv
obj-m := milianke_jpeg_a.o milianke_jpeg_b.o milianke_jpeg_c.o
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) KBUILD_EXTRA_SYMBOLS=$(SGDMA_DIR)/Module.symvers modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
