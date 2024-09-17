NVCCFLAGS=-arch=sm_80 -I../libgeminiFs_src -I../src/include -I../src/ -I../src/linux -I../src/freestanding/include -O3 $(CXXFLAGS)
LDFLAGS=-L../build/lib -Xlinker -rpath=$(shell pwd)/../build/lib -lgeminiFs -lnvm -arch=sm_80

all: TestForNoBackingPagecache.exe TestForNvmeBacking.exe TestForPageCache.exe TestForNvmeofstRefining.exe

clean:
	rm -f *.exe

TestForNvmeofstRefining.exe: TestForNvmeofstRefining.cu
	nvcc $(LDFLAGS) $(NVCCFLAGS) TestForNvmeofstRefining.cu -o TestForNvmeofstRefining.exe

TestForNvmeBacking.exe: TestForNvmeBacking.cu
	nvcc $(LDFLAGS) $(NVCCFLAGS) TestForNvmeBacking.cu -o TestForNvmeBacking.exe

TestForNoBackingPagecache.exe: TestForNoBackingPagecache.cu
	nvcc $(LDFLAGS) $(NVCCFLAGS) TestForNoBackingPagecache.cu -o TestForNoBackingPagecache.exe

TestForPageCache.exe: TestForPageCache.cu
	nvcc $(LDFLAGS) $(NVCCFLAGS) TestForPageCache.cu -o TestForPageCache.exe

TestForODIRECT.exe: TestForODIRECT.cu
	nvcc $(LDFLAGS) $(NVCCFLAGS) TestForODIRECT.cu -o TestForODIRECT.exe
