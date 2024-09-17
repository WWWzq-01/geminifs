#ifndef API_GPU_CU_H
#define API_GPU_CU_H

#include <errno.h>
#include <string.h>
#include "fs_calls.cu.h"
#include "host_loop.h"
#include "fs_initializer.cu.h"
#include <cuda.h>
#include <cuda_runtime.h>
#include <stdio.h>
#include "api.h"

#ifndef CUDA_SAFE_CALL
#define CUDA_SAFE_CALL(err)  __checkCudaErrors (err, __FILE__, __LINE__)
#endif
struct DeviceData {
    char* d_filename;
    size_t* d_offset;
    size_t* d_size;
};


#endif // API_GPU_CU_H