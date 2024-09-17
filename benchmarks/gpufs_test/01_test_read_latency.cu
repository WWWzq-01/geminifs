#include <stdio.h>
#include <errno.h>

#include "fs_calls.cu.h"
#include "host_loop.h"

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

#define MAX_READ_IO_NUM (10000)
#define MAX_TRIALS (10000)
typedef long long ll;
size_t pageSize = 1 << 12;	// 4k
size_t memSize = pageSize * 2048; // 4M
ll fileSize = 1LL << 35;	// 32GB
int device = 1;

__shared__ uchar* scratch;

__global__ void read(char* filename, ll *offset, size_t *size, void* buffer_addr)
{
	clock_t start, end;
	double duration;
	if(threadIdx.x==0)
		start = clock();
	__shared__ int fd;
	fd = 0;
	fd = gopen(filename, O_GRDONLY | O_DIRECT);	//only open once
	if (fd < 0)
			ERROR("Failed to open file");

	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	ll off = *offset + tid * FS_BLOCKSIZE;

	if (FS_BLOCKSIZE != gread(fd, off , FS_BLOCKSIZE, (uchar*)buffer_addr + tid * FS_BLOCKSIZE))
		assert(NULL);
	
	__syncthreads();
	
	gclose(fd);
	if(threadIdx.x==0)
	{
		end = clock();
		duration = (double)(end - start) / (double)1000;
		printf("Thread latency: %.3f us\n", duration);
	}
}
void test_read_latency(char* h_filename, int nblocks, int nthreads, int trials)
{    
 	
	char* d_filename = NULL;
	void* scratch_dev = NULL;
	size_t* d_size = NULL;
	// size_t mem_size;
	int* d_fd= NULL;
	void* scratch_gpu = NULL;
	// copy param to device
	CUDA_SAFE_CALL(cudaMalloc(&d_filename, strlen(h_filename)+1));
    CUDA_SAFE_CALL(cudaMemcpy(d_filename, h_filename, strlen(h_filename) + 1, cudaMemcpyHostToDevice));

	int cnt = 0;
    ll* d_offset = NULL;
    CUDA_SAFE_CALL(cudaMalloc(&d_offset, sizeof(long long)));


	CUDA_SAFE_CALL(cudaMalloc(&d_size, sizeof(size_t)));
    CUDA_SAFE_CALL(cudaMemcpy(d_size, &memSize, sizeof(size_t), cudaMemcpyHostToDevice)); 


	scratch =  (uchar*) aligned_alloc(memSize, pageSize);
	CUDA_SAFE_CALL(cudaMalloc(&scratch_dev, sizeof(u_int64_t)));
	CUDA_SAFE_CALL(cudaMemcpy(scratch_dev, &scratch, sizeof(u_int64_t), cudaMemcpyHostToDevice));

	CUDA_SAFE_CALL(cudaMalloc(&scratch_gpu, memSize));
	
	volatile GPUGlobals* gpuGlobals;
	initializer(&gpuGlobals);
	for (int i = 0; i < trials; i++)
	{
		for(ll offset=0; offset < fileSize; offset += nthreads*nblocks*pageSize)
		{
			
			CUDA_SAFE_CALL(cudaMemcpy(d_offset, &offset, sizeof(long long), cudaMemcpyHostToDevice));

			double time_before = _timestamp();
			
			read<<<nblocks,nthreads,0,gpuGlobals->streamMgr->kernelStream>>>(d_filename, d_offset, d_size,(void *)scratch_gpu);
			run_gpufs_handler(gpuGlobals, device);
			cudaError_t error = cudaDeviceSynchronize();
			if (error != cudaSuccess)
				printf("Device failed, CUDA error message is: %s\n\n",cudaGetErrorString(error));

			double time_after = _timestamp();
					
			// reset
			CUDA_SAFE_CALL(cudaMemset(scratch_gpu, 0, memSize));

			cnt++;
			if(cnt == MAX_READ_IO_NUM)
				break;
			
		}
		if(cnt == MAX_READ_IO_NUM)
			break;
	}
	
	
	delete gpuGlobals;
    if(d_offset)
        CUDA_SAFE_CALL(cudaFree(d_offset));
    if(d_filename)
        CUDA_SAFE_CALL(cudaFree(d_filename));
    if(d_size)
        CUDA_SAFE_CALL(cudaFree(d_size));
}

int main(int argc, char** argv)
{
	char* gpudev = getenv("GPUDEVICE");
	if (gpudev != NULL)
		device = atoi(gpudev);
	device = 0;
	CUDA_SAFE_CALL(cudaSetDevice(device));
	cudaDeviceProp deviceProp;
	CUDA_SAFE_CALL(cudaGetDeviceProperties(&deviceProp, device));
	// printDeviceInfo(deviceProp);

	// printf("Running on device %d: \"%s\"\n", device, deviceProp.name);

	if (argc < 5)
	{
		fprintf(stderr, "Usage: <kernel_iterations> <blocks> <threads> filename\n");
		return -1;
	}

	int trials = atoi(argv[1]);
	assert(trials <= MAX_TRIALS);
	int nblocks = atoi(argv[2]);
	int nthreads = atoi(argv[3]);
	char* filename = argv[4];
	fprintf(stderr, "\tfilename %s: iterations %d, blocks %d, threads %d\n", filename, trials, nblocks, nthreads);
	// for (int i = 1; i < trials + 1; i++)
	// {
	test_read_latency(filename, nblocks, nthreads, trials);

    

}