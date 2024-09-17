
#include <cassert>
#include <iostream>
#include <ctime>
#include "geminifs_api.cuh"


#ifndef CUDA_SAFE_CALL
#define CUDA_SAFE_CALL(err)  __checkCudaErrors (err, __FILE__, __LINE__)
#endif

inline void __checkCudaErrors(cudaError err, const char *file, const int line)
{
	if (cudaSuccess != err)
	{
		fprintf(stderr, "%s(%i) : CUDA Runtime API error %d: %s.\n", file, line, (int) err, cudaGetErrorString(err));
		exit(-1);
	}
}

#define snvme_control_path "/dev/snvm_control"
#define snvme_path "/dev/snvme2"
#define nvme_mount_path "/home/qs/nvm_mount"
#define nvme_dev_path "/dev/nvme1n1"


#define geminifs_file_name "checkpoint.geminifs"
#define geminifs_file_path (nvme_mount_path "/" geminifs_file_name)

size_t virtual_space_size = 1 * (1ull << 20); /*GB*/
size_t page_capacity = 16 * (1ull << 10);
size_t file_block_size = 4096;
int log_dev_page_size = 12;
size_t dev_page_size =  (1ull << log_dev_page_size);

void test_device_read_latency(host_fd_t host_fd, int iterations, int nblocks, int nthreads, size_t log_dev_page_size)
{
    // prepare dev buffer
    uint64_t *dev_buf;
    dev_page_size = (1ull << log_dev_page_size);

    uint64_t chunk_size = dev_page_size;
    CUDA_SAFE_CALL(cudaMalloc(&dev_buf, virtual_space_size));

    dev_fd_t dev_fd = host_open_geminifs_file_for_device(host_fd, page_capacity, dev_page_size);
    
    for (int i = 0; i < iterations; i++)
    {
        // nblocks*nthreads read chunk_size each
        for (vaddr_t offset = 0; offset < virtual_space_size; offset += chunk_size)
        {
            // TD: 改为__device__
            device_xfer_geminifs_file<<<nblocks, nthreads>>>(dev_fd, offset, dev_buf + chunk_size, chunk_size, 1);
            cudaDeviceSynchronize();

        }
        CUDA_SAFE_CALL(cudaMemset(dev_buf, 0, virtual_space_size));
    }
    if(dev_buf)
        CUDA_SAFE_CALL(cudaFree(dev_buf));

}
int main(int argc, char** argv)
{
    if(argc < 5)
    {
        fprintf(stderr, "<iterations> <nblocks> <nthreads> <log_dev_page_size>\n");
        return -1;
    }
    int iterations = atoi(argv[1]);
    int nblocks = atoi(argv[2]);
    int nthreads = atoi(argv[3]);
    int log_dev_page_size = atoi(argv[4]);
    srand(time(0));
    int rand_start = rand();
    
    host_open_all(snvme_control_path, snvme_path, nvme_dev_path, nvme_mount_path, 1, 1024, 32);
    

    remove(geminifs_file_path);

    host_fd_t host_fd = host_create_geminifs_file(geminifs_file_path, file_block_size, virtual_space_size);
    host_refine_nvmeofst(host_fd);

    // host write data to file
    uint64_t *host_buf = (uint64_t *)malloc(virtual_space_size);
    for (size_t i = 0; i < virtual_space_size / sizeof(uint64_t); i++)
        host_buf[i] = rand_start + i;
    host_xfer_geminifs_file(host_fd, 0, host_buf, virtual_space_size, 0);
    
    // device read data from file
    test_device_read_latency(host_fd, iterations, nblocks, nthreads, log_dev_page_size);
   

}
