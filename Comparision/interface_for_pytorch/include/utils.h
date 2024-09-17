#include <errno.h>
#include <string.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <stdio.h>

#ifndef CUDA_SAFE_CALL
#define CUDA_SAFE_CALL(err)  __checkCudaErrors (err, __FILE__, __LINE__)
#endif

struct DeviceData {
    char* d_filename;
    size_t* d_offset;
    size_t* d_size;
};

void init_device_app();
void init_app();
DeviceData copy_data_to_device(const char* h_filename, size_t h_offset, size_t h_size);
char* copy_string_to_device(const char* h_str);