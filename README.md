# Ganymede

## libmldk
CPU lib for parsing the MLDK format
GPU lib for parsing the MLDK format in GPU
## src
bam src to construct the GPU-NVMe path
## kernel_module
Modifield NVMe Module for CPU/GPU Share
MLDK.ko used for metedata acquire and allocation

## Comparision
GPUfs
GPUfs + GDS
## benchmarks
Fio
GPU Fio
Bam benchs
Dataset Load
CheckPoints load/restore



### System Configurations ###
* As mentioned above, `Above 4G Decoding` needs to be ENABLED in the BIOS
* The system's IOMMU should be disabled for ease of debugging.
  * In Intel Systems, this requires disabling `Vt-d` in the BIOS
  * In AMD Systems, this requires disabling `IOMMU` in the BIOS
* The `iommu` support in Linux must be disabled too, which can be checked and disabled following the instructions [below](#disable-iommu-in-linux).
* In the system's BIOS, `ACS` must be disabled if the option is available
* Relatively new Linux kernel (ie. 5.x).
* CMake 3.10 or newer and the _FindCUDA_ package for CMake
* GCC version 5.4.0 or newer. Compiler must support C++11 and POSIX threads.
* CUDA 12.3 or newer
* Nvidia driver (at least 440.33 or newer)
* The kernel version we have tested is 5.8.x. A newer kernel like 6.x may not work with BaM as the kernel APIs have dramatically changed. 
* Kernel module symbols and headers for the Nvidia driver. The instructions for how to compile these symbols are given [below](#compiling-nvidia-driver-kernel-symbols).

### Disable IOMMU in Linux ###
If you are using CUDA or implementing support for your own custom devices, 
you need to explicitly disable IOMMU as IOMMU support for peer-to-peer on 
Linux is a bit flaky at the moment. If you are not relying on peer-to-peer,
we would in fact recommend you leaving the IOMMU _on_ for protecting memory 
from rogue writes.

To check if the IOMMU is on, you can do the following:

```
$ cat /proc/cmdline | grep iommu
```

If either `iommu=on` or `intel_iommu=on` is found by `grep`, the IOMMU
is enabled.

You can disable it by removing `iommu=on` and `intel_iommu=on` from the 
`CMDLINE` variable in `/etc/default/grub` and then reconfiguring GRUB.
The next time you reboot, the IOMMU will be disabled.

### Compiling Nvidia Driver Kernel Symbols ###
Typically the Nvidia driver kernel sources are installed in the `/usr/src/` directory.
So if the Nvidia driver version is `550.54.15`, then they will be in the `/usr/src/nvidia-550.54.15` directory.
So assuming the driver version is `550.54.15`, to get the kernel symbols you need to do the following commands as the `root` user.

```
$ cd /usr/src/nvidia-550.54.15/
$ sudo make
```

Building the Project
-------------------------------------------------------------------------------
From the project root directory, do the following:
```
$ git submodule update --init --recursive
$ mkdir -p build; cd build
$ cmake ..                            
$ make tools                          # builds test tools
$ make libnvm                        # builds library
$ make benchmarks                     # builds benchmark program
```

The CMake configuration is _supposed to_ autodetect the location of CUDA, 
Nvidia driver and project library. CUDA is located by the _FindCUDA_ package for
CMake, while the location of both the Nvidia driver can be manually
set by overriding the `NVIDIA` defines for CMake 
(`cmake .. -DNVIDIA=/usr/src/nvidia-550.54.15/`).