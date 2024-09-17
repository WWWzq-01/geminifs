# SPDX-License-Identifier: GPL-2.0

KVER ?= $(shell uname -r)
# Try to get it based on available nvidia module version (just in case there are sources for couple of versions)
nv_version=$(shell /sbin/modinfo -F version -k $(KVER) nvidia 2>/dev/null)
nv_sources=$(shell /bin/ls -d /usr/src/nvidia-$(nv_version)/ 2>/dev/null)
ifneq ($(shell test -d "$(nv_sources)" && echo "true" || echo "" ),)
	NVIDIA_SRC_DIR ?= $(shell find "$(nv_sources)" -name "nv-p2p.h"|head -1|xargs dirname || echo "NVIDIA_DRIVER_MISSING")
else
	NVIDIA_SRC_DIR ?= $(shell find /usr/src/nvidia-* -name "nv-p2p.h"|head -1|xargs dirname || echo "NVIDIA_DRIVER_MISSING")
endif

obj-m += snvme-core.o
obj-m += snvme.o
# nvme-core.objs := ioctl.o multipath.o core.o
# nvme.objs := pci.o
ccflags-y += -I../../../src/linux
ccflags-y += -I$(NVIDIA_SRC_DIR)

#   @ cd ../../../scripts
# 	@ ./create_nv.symvers.sh
# 	@ cat nv.symvers >> Module.symvers


snvme-core-y				:= core.o ioctl.o snvme_help.o
snvme-core-$(CONFIG_NVME_MULTIPATH)	+= multipath.o
snvme-core-$(CONFIG_BLK_DEV_ZONED)	+= zns.o
snvme-core-$(CONFIG_FAULT_INJECTION_DEBUG_FS)	+= fault_inject.o
snvme-core-$(CONFIG_NVME_HWMON)		+= hwmon.o

snvme-objs := nvfs-pci.o nvfs-p2p.o list.o ctrl.o map.o pci.o 


KERNEL_SRC := /home/qs/linux-5.15/linux
# /lib/modules/$(shell uname -r)/build/
# nvme-core-y	:= core.o ioctl.o multipath.o
# nvme-y := pci.o
all:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules
clean:
	rm -fr *.o *.ko *.mod* .*.cmd .*.d