#!/bin/bash -x


# 1. For libnvm.so
#mkdir -p build
#cd build
#cmake ..
#make -j
#make bench_test -j
#cd ..

# 2. For libgeminiFs.a
cd libgeminiFs_src
make clean
make -j
cd ..
cp libgeminiFs_src/libgeminiFs.a ./build/lib


# 3. For examples
cd examples
make clean
make -j CXXFLAGS="-DNR_WARPS=96 -DNR_ACQUIRE_PAGES=4 -DNR_PAGES__PER_WARP=512"
