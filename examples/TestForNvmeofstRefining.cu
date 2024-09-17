
#include <cassert>
#include <iostream>
#include "geminifs_api.cuh"


#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

#define snvme_control_path "/dev/snvm_control"
#define snvme_path "/dev/snvme2"
#define nvme_mount_path "/home/qs/nvm_mount"
#define nvme_dev_path "/dev/nvme1n1"


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
            32);

  size_t virtual_space_size = 16 * (1ull << 10)/*GB*/;
  size_t page_capacity = 4 * (1ull << 10);
  size_t file_block_size = 4096;
  size_t dev_page_size = 4096;
  //size_t virtual_space_size = 4096;

  remove(geminifs_file_path);

  host_fd_t host_fd = host_create_geminifs_file(geminifs_file_path, file_block_size, virtual_space_size);

  host_refine_nvmeofst(host_fd);
  host_close_geminifs_file(host_fd);

  host_close_all();

  return 0;
}

