#ifndef GEMINIFS_H
#define GEMINIFS_H

#ifdef __cplusplus
extern "C"{
#endif

#include <stdint.h>

typedef uint64_t vaddr_t;
typedef uint64_t rawfile_ofst_t;
typedef uint64_t nvme_ofst_t;

struct geminiFS_hdr {
  uint64_t magic_num;
  uint64_t virtual_space_size; /* in bytes */
  uint8_t block_bit; /* block_size, in the form of bit num */
  uint64_t nr_l1;
  rawfile_ofst_t first_block_base; /* or length of metadata */
  int fd; /* dummy */
  nvme_ofst_t l1[];
};

extern union geminiFS_magic {
  uint64_t magic_num;
  char magic_cstr[8];
} the_geminiFS_magic;

typedef int fd_t;
typedef struct geminiFS_hdr *host_fd_t;

//using dev_fd_t = PageCache *;
typedef void *dev_fd_t;

//-----------------host only------------------
extern void
host_open_all(
        const char *snvme_control_path,
        const char *snvme_path,
        const char *nvme_dev_path,
        const char *mount_path,
        uint32_t ns_id,
        uint64_t queueDepth,
        uint64_t numQueues);

extern host_fd_t
host_create_geminifs_file(const char *filename,
                          uint64_t block_size,
                          uint64_t virtual_space_size);
extern host_fd_t
host_create_geminifs_file_1(const char *filename,
                          uint64_t block_size,
                          uint64_t page_size,
                          uint64_t virtual_space_size);

extern host_fd_t
host_open_geminifs_file(const char *filename);

extern size_t
host_xfer_geminifs_file(host_fd_t fd_1,
                        vaddr_t va,
                        void *buf_1,
                        size_t nbyte,
                        int is_read);

extern void
host_refine_nvmeofst(host_fd_t fd);

extern void
host_close_geminifs_file(host_fd_t fd);

extern void
host_close_all();

//-----------------host for device------------------
extern dev_fd_t
host_open_geminifs_file_for_device(
        host_fd_t host_fd,
        uint64_t pagecache_capacity,
        int page_size,
        int pagecache_batching_size);

extern dev_fd_t
host_open_geminifs_file_for_device_1(
        host_fd_t host_fd,
        double cache_ratio,
        int page_size,
        int pagecache_batching_size);

extern dev_fd_t
host_open_geminifs_file_for_device_without_backing_file(
        int page_size,
        uint64_t pagecache_capacity,
        int pagecache_batching_size);

extern dev_fd_t
host_get_pagecache__for_test_evicting(
        uint64_t fake_file_size,
        uint64_t pagecache_capacity,
        int page_size,
        int pagecache_batching_size);

#ifdef __cplusplus
}
#endif

#endif
