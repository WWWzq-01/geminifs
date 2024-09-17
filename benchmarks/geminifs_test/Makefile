NVCCFLAGS=-arch=sm_80 -I../../libgeminiFs_src -O3
LDFLAGS=-L../../build/lib -Xlinker -rpath=$(shell pwd)/../../build/lib -lgeminiFs -lnvm -arch=sm_80

all: 01_test_read_latency 02_test_write_latency

clean:
	rm -f 01_test_read_latency
	rm -f 02_test_write_latency
	rm -f *.o *.a


01_test_read_latency: 01_test_read_latency.cu
	nvcc $(LDFLAGS) $(NVCCFLAGS) 01_test_read_latency.cu -o 01_test_read_latency

02_test_write_latency: 02_test_write_latency.cu
	nvcc $(LDFLAGS) $(NVCCFLAGS) 02_test_write_latency.cu -o 02_test_write_latency

