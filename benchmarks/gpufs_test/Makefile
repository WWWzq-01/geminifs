#/* 
#* This expermental software is provided AS IS. 
#* Feel free to use/modify/distribute, 
#* If used, please retain this disclaimer and cite 
#* "GPUfs: Integrating a file system with GPUs", 
#* M Silberstein,B Ford,I Keidar,E Witchel
#* ASPLOS13, March 2013, Houston,USA
#*/

CUDA_ROOT:=/usr/local/cuda
GPUFSROOTDIR?=../../Comparision/gpufs/

GPUFSINCLUDEDIR=$(GPUFSROOTDIR)/include
GPUFSLIBDIR=$(GPUFSROOTDIR)/lib

CUDA_INCLUDE=-I$(GPUFSROOTDIR)/include -I$(CUDA_ROOT)/include
CUDA_LIB=-L$(GPUFSROOTDIR)/lib -L$(CUDA_ROOT)/lib64 -lgpufs -lcudart

CXXFLAGS=-O2 $(CUDA_INCLUDE) $(CUDA_LIB)
NVCCFLAGS=-O2 $(CUDA_INCLUDE) $(CUDA_LIB) --std=c++11 --generate-code code=sm_80,arch=compute_80 -maxrregcount 32 -Xptxas -dlcm=cg

NVCC=$(CUDA_ROOT)/bin/nvcc

# get_device_info: get_device_info.o
# 	$(NVCC) $(NVCCFLAGS) --cudart static -link -o "get_device_info" get_device_info.o

# get_device_info.o: get_device_info.cu
# 	$(NVCC) $(NVCCFLAGS) -dc get_device_info.cu -o get_device_info.o

# 01_test_read_latency: 01_test_read_latency.o
# 	$(NVCC) $(NVCCFLAGS) --cudart static -link -o "01_test_read_latency" 01_test_read_latency.o

# 01_test_read_latency.o: 01_test_read_latency.cu
# 	$(NVCC) $(NVCCFLAGS) -dc 01_test_read_latency.cu -o 01_test_read_latency.o

02_test_read_bandwidth: 02_test_read_bandwidth.o
	$(NVCC) $(NVCCFLAGS) --cudart static -link -o "02_test_read_bandwidth" 02_test_read_bandwidth.o

02_test_read_bandwidth.o: 02_test_read_bandwidth.cu
	$(NVCC) $(NVCCFLAGS) -dc 02_test_read_bandwidth.cu -o 02_test_read_bandwidth.o

PHONY:  clean

clean:
	rm -f 01_test_read_latency *.o *.a
	rm -f 02_test_read_bandwidth *.o *.a
