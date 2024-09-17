#ifndef GEMINIFS_CUH
#define GEMINIFS_CUH

#include "geminifs_api.h"


extern __global__ void
device_xfer_geminifs_file(dev_fd_t fd_1,
                          vaddr_t va,
                          void *buf_dev,
                          size_t nbyte,
                          int is_read,
                          int nr_acquire_pages = 16);

extern __global__ void
device_sync(dev_fd_t);

#endif
