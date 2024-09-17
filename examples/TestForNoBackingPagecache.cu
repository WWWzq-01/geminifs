
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
  int page_size = 64 * (1ull << 10); /* 32k */


  int nr_warps = NR_WARPS;
  size_t nr_pages = nr_warps * NR_PAGES__PER_WARP;
  size_t capacity = nr_pages * page_size;

  gpuErrchk(cudaSetDevice(0));

  size_t heapsz = 1 * (1ull << 30);
  gpuErrchk(cudaDeviceSetLimit(cudaLimitMallocHeapSize, heapsz));

  dev_fd_t dev_fd =
      host_open_geminifs_file_for_device_without_backing_file(page_size, capacity, nr_warps);

  //size_t buf_size = 128 * (1ull << 10); /* 128kB */
  size_t buf_size = capacity;

  uint64_t *whole_host_buf = (uint64_t *)malloc(capacity);
  uint64_t *another_whole_host_buf = (uint64_t *)malloc(capacity);

  uint64_t *dev_buf1;
  uint64_t *dev_buf2;
  gpuErrchk(cudaMalloc(&dev_buf1, buf_size));
  gpuErrchk(cudaMalloc(&dev_buf2, buf_size));

  for (size_t i = 0; i < capacity / sizeof(uint64_t); i++)
    whole_host_buf[i] = i + 2;

  for (vaddr_t va = 0; va < capacity; va += buf_size) {
      gpuErrchk(cudaMemcpy(dev_buf1, (uint8_t *)whole_host_buf + va, buf_size, cudaMemcpyHostToDevice));
      cudaDeviceSynchronize();

      GpuTimer gpu_timer;

      gpu_timer.Start();
      device_xfer_geminifs_file<<<nr_warps, 32>>>(dev_fd, va, dev_buf1, buf_size, 0, NR_ACQUIRE_PAGES);
      gpu_timer.Stop();

      float time = gpu_timer.Elapsed();
      float bw = ((float)2 * buf_size * 1000) / (time * (1ull << 30));
      std::cout << "bw:" << bw << "GB per s" << std::endl;

      cudaDeviceSynchronize();
  }

  for (vaddr_t va = 0; va < capacity; va += buf_size) {
      GpuTimer gpu_timer;

      gpu_timer.Start();
      device_xfer_geminifs_file<<<nr_warps, 32>>>(dev_fd, va, dev_buf2, buf_size, 1, NR_ACQUIRE_PAGES);
      gpu_timer.Stop();

      float time = gpu_timer.Elapsed();
      float bw = ((float)2 * buf_size * 1000) / (time * (1ull << 30));
      std::cout << "bw:" << bw << "GB per s" << std::endl;

      cudaDeviceSynchronize();
      gpuErrchk(cudaMemcpy((uint8_t *)another_whole_host_buf + va, dev_buf2, buf_size, cudaMemcpyDeviceToHost));
      cudaDeviceSynchronize();
  }

  for (size_t i = 0; i < capacity / sizeof(uint64_t); i++) {
      assert(another_whole_host_buf[i] == i + 2);
  }

  return 0;
}

