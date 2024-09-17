#include <cassert>
#include <iostream>

#include "geminifs_api.cuh"

struct GpuTimer
{
      cudaEvent_t start;
      cudaEvent_t stop;

      GpuTimer() {
            cudaEventCreate(&start);
            cudaEventCreate(&stop);
      }

      ~GpuTimer() {
            cudaEventDestroy(start);
            cudaEventDestroy(stop);
      }

      void Start() {
            cudaEventRecord(start, 0);
      }

      void Stop() {
            cudaEventRecord(stop, 0);
      }

      float Elapsed() {
            float elapsed;
            cudaEventSynchronize(stop);
            cudaEventElapsedTime(&elapsed, start, stop);
            return elapsed;
      }
};

#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

int
main() {
  int nr_warps = 16;
  size_t nr_pages = nr_warps * 32;
  size_t page_size = 128 * (1ull << 10)/*KB*/;
  size_t page_capacity = nr_pages * page_size;
  size_t virtual_space_size = page_capacity * 64;

  uint64_t *dev_buf1;
  uint64_t *dev_buf2;

  gpuErrchk(cudaMallocManaged(&dev_buf1, virtual_space_size));
  gpuErrchk(cudaMallocManaged(&dev_buf2, virtual_space_size));

  dev_fd_t dev_fd = host_get_pagecache__for_test_evicting(virtual_space_size, page_capacity, page_size, nr_warps);

  //device_xfer_geminifs_file<<<nr_warps, 32>>>(dev_fd, 0, dev_buf1, virtual_space_size, 0);
  //cudaDeviceSynchronize();
  device_xfer_geminifs_file<<<nr_warps, 32>>>(dev_fd, 0, dev_buf2, virtual_space_size, 1);
  cudaDeviceSynchronize();

  return 0;
}

