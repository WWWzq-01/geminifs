#include "utils.h"

// void init_device_app()
// {

// 	CUDA_SAFE_CALL(cudaDeviceSetLimit(cudaLimitMallocHeapSize, 1 << 30));
// }
// void init_app()
// {
// 	void* d_OK;
// 	CUDA_SAFE_CALL(cudaGetSymbolAddress(&d_OK, OK));
// 	CUDA_SAFE_CALL(cudaMemset(d_OK, 0, sizeof(int)));
// 	// INITI LOCK   
// 	void* inited;

// 	CUDA_SAFE_CALL(cudaGetSymbolAddress(&inited, sync_sem));
// 	CUDA_SAFE_CALL(cudaMemset(inited, 0, sizeof(LAST_SEMAPHORE)));
// }



DeviceData copy_data_to_device(const char* h_filename, size_t h_offset, size_t h_size) 
{
    DeviceData device_data;

    // Copy filename to device	
	CUDA_SAFE_CALL(cudaMalloc(&device_data.d_filename, strlen(h_filename)+1));
    CUDA_SAFE_CALL(cudaMemcpy(device_data.d_filename, h_filename, strlen(h_filename) + 1, cudaMemcpyHostToDevice));

    // Copy offset to device
    CUDA_SAFE_CALL(cudaMalloc(&device_data.d_offset, sizeof(size_t)));
    CUDA_SAFE_CALL(cudaMemcpy(device_data.d_offset, &h_offset, sizeof(size_t), cudaMemcpyHostToDevice));

    // Copy size to device
    CUDA_SAFE_CALL(cudaMalloc(&device_data.d_size, sizeof(size_t)));
    CUDA_SAFE_CALL(cudaMemcpy(device_data.d_size, &h_size, sizeof(size_t), cudaMemcpyHostToDevice));

    return device_data;
}

char* copy_string_to_device(const char* h_str) 
{
    int n = strlen(h_str);
    assert(n > 0);
    char* d_str;
    CUDA_SAFE_CALL(cudaMalloc(&d_str, n + 1));
    CUDA_SAFE_CALL(cudaMemcpy(d_str, h_str, n + 1, cudaMemcpyHostToDevice));
    return d_str;
}