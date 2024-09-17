#!/bin/bash -x
sudo rmmod libnvm
cd ../../Comparision/bam/build/module/
sudo make unload
echo "0000:63:00.0" >> /sys/bus/pci/drivers/nvme/bind
