#!/bin/bash


#set -x

for NR_WARPS in 64 128; do
  for NR_PAGES__PER_WARP in 16 32; do
    for NR_ACQUIRE_PAGES in 8 16; do
      CXXFLAGS="-DNR_WARPS=${NR_WARPS} -DNR_ACQUIRE_PAGES=${NR_ACQUIRE_PAGES} -DNR_PAGES__PER_WARP=${NR_PAGES__PER_WARP}"
      echo $CXXFLAGS

      cd libgeminiFs_src
      #make clean
      make -j > /dev/null 2>&1
      cd ..
      cp libgeminiFs_src/libgeminiFs.a ./build/lib
      
      
      # 3. For examples
      cd examples
      make clean
      make -j CXXFLAGS="${CXXFLAGS}" > /dev/null 2>&1
      ./TestForNoBackingPagecache.exe | grep bw
      cd ..
    done
  done
done
exit


