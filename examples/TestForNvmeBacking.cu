
#include <cassert>
#include <iostream>
#include <ctime>
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

#define my_assert(code) do { \
    if (!(code)) { \
        host_close_all(); \
        exit(1); \
    } \
} while(0)


#define snvme_control_path "/dev/snvm_control"
#define snvme_path "/dev/snvme1"
#define nvme_mount_path "/home/qs/nvm_mount"
#define nvme_dev_path "/dev/nvme0n1"


#define geminifs_file_name "checkpoint.geminifs"
#define geminifs_file_path (nvme_mount_path "/" geminifs_file_name)


int
main() {
    host_open_all(
            snvme_control_path,
            snvme_path,
            nvme_dev_path,
            nvme_mount_path,
            1,
            1024,
            64);

    int nr_warps = NR_WARPS;

  size_t file_block_size = 4 * (1ull << 10);
  size_t dev_page_size = 128 * (1ull << 10);


  size_t nr_pages = nr_warps * NR_PAGES__PER_WARP;
  size_t page_capacity = nr_pages * dev_page_size;
  size_t virtual_space_size = page_capacity * 8;

  srand(time(0));
  int rand_start = rand();

  remove(geminifs_file_path);

  host_fd_t host_fd = host_create_geminifs_file(geminifs_file_path, file_block_size, virtual_space_size);
  host_refine_nvmeofst(host_fd);

  uint64_t *buf1 = (uint64_t *)malloc(virtual_space_size);
  for (size_t i = 0; i < virtual_space_size / sizeof(uint64_t); i++)
      buf1[i] = rand_start + i;
  host_xfer_geminifs_file(host_fd, 0, buf1, virtual_space_size, 0);
  
  uint64_t *buf2 = (uint64_t *)malloc(virtual_space_size);
  host_xfer_geminifs_file(host_fd, 0, buf2, virtual_space_size, 1);
  for (size_t i = 0; i < virtual_space_size / sizeof(uint64_t); i++)
      my_assert(buf2[i] == rand_start + i);

  host_close_geminifs_file(host_fd);

  host_fd = host_open_geminifs_file(geminifs_file_path);

  uint64_t *dev_buf1;
  uint64_t *dev_buf2;

  //gpuErrchk(cudaMallocManaged(&dev_buf1, virtual_space_size));
  gpuErrchk(cudaMallocManaged(&dev_buf2, virtual_space_size));

  dev_fd_t dev_fd = host_open_geminifs_file_for_device(host_fd, page_capacity, dev_page_size, nr_warps);
  double elasped_time = ({
          GpuTimer gputimer;
          gputimer.Start();
          device_xfer_geminifs_file<<<NR_WARPS, 32>>>(dev_fd, 0, dev_buf2, virtual_space_size, 1, NR_ACQUIRE_PAGES);
          gputimer.Stop();
          cudaDeviceSynchronize();
          gputimer.Elapsed();
  });

  double bw = ((float)virtual_space_size * 1000) / (elasped_time * (1ull << 30));
  std::cout << "time: " << elasped_time << "ms " << "bw: " << bw << "GB per s" << std::endl;


  //uint64_t *buf3 = (uint64_t *)malloc(virtual_space_size);

  //for (size_t i = 0; i < virtual_space_size / sizeof(uint64_t); i++)
  //    my_assert(dev_buf2[i] == rand_start + i);
  
  //cudaDeviceSynchronize();


  host_close_geminifs_file(host_fd);

  printf("ALL OK!\n");

out:
  host_close_all();

  return 0;
}

