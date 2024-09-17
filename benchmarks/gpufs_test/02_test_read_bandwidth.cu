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
ll memSize = pageSize; // 4M
ll fileSize = 1LL << 38;	// 256GB
int device = 0;

__shared__ uchar* scratch;

__global__ void read(char* filename, ll *offset, size_t *size, void* buffer_addr)
{
    // clock_t start, end;
	// double duration;
	// if(threadIdx.x==0)
	// 	start = clock();
	__shared__ int fd;
	fd = 0;
	fd = gopen(filename, O_GRDONLY | O_DIRECT);	//only open once
	if (fd < 0)
			ERROR("Failed to open file");

	int tid = blockIdx.x * blockDim.x + threadIdx.x;
    size_t io_size = *(size);
	ll off = *offset + tid * io_size;

	if (io_size != gread(fd, off , io_size, (uchar*)buffer_addr + tid * io_size))
		assert(NULL);
	
	__syncthreads();
	
	gclose(fd);
    // if(threadIdx.x==0)
	// {
	// 	end = clock();
	// 	duration = (double)(end - start) / (double)1000;
	// 	printf("Latency: %.3f us, Bandwidth: %.3f MB/s\n", duration ,((double)io_size * 1000 * 1000) / (duration * 1024 * 1024));
	// }
}
void test_read_latency_bandwidth(char* h_filename, int nblocks, int nthreads, int iterations, size_t io_size)
{    
 	
	char* d_filename = NULL;
	void* scratch_dev = NULL;
	size_t* d_size = NULL;
    ll* d_offset = NULL;
    int cnt = 0;
	int* d_fd= NULL;

	// copy param to device
	CUDA_SAFE_CALL(cudaMalloc(&d_filename, strlen(h_filename)+1));
    CUDA_SAFE_CALL(cudaMemcpy(d_filename, h_filename, strlen(h_filename) + 1, cudaMemcpyHostToDevice));

	CUDA_SAFE_CALL(cudaMalloc(&d_size, sizeof(size_t)));
    CUDA_SAFE_CALL(cudaMemcpy(d_size, &io_size, sizeof(size_t), cudaMemcpyHostToDevice)); 

    CUDA_SAFE_CALL(cudaMalloc(&d_offset, sizeof(long long)));

    memSize = io_size * nblocks * nthreads;
	CUDA_SAFE_CALL(cudaMalloc(&scratch_dev, memSize));
	
	volatile GPUGlobals* gpuGlobals;
	initializer(&gpuGlobals);
	for (int i = 0; i < iterations; i++)
	{
		for(ll offset=0; offset < fileSize; offset += nthreads * nblocks * io_size)
		{
			
			CUDA_SAFE_CALL(cudaMemcpy(d_offset, &offset, sizeof(long long), cudaMemcpyHostToDevice));

			double time_before = _timestamp();
			
			read<<<nblocks,nthreads,0,gpuGlobals->streamMgr->kernelStream>>>(d_filename, d_offset, d_size,(void *)scratch_dev);
			run_gpufs_handler(gpuGlobals, device);
			cudaError_t error = cudaDeviceSynchronize();
			if (error != cudaSuccess)
            {
                printf("Device failed, CUDA error message is: %s\n\n",cudaGetErrorString(error));
                exit(-1);
            }
				
			double time_after = _timestamp();
            double elapsed = time_after - time_before;

			printf("Latency: %.3f us, Bandwidth: %.3f MB/s\n", elapsed, ((double)memSize * 1000 * 1000) / (elapsed * 1024 * 1024));
			
			// reset
			CUDA_SAFE_CALL(cudaMemset(scratch_dev, 0, memSize));

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

	if (argc < 5)
	{
		fprintf(stderr, "filename <iterations> <blocks> <threads> <io_size>(optional, default: 4096)\n");
		return -1;
	}
    char* filename = argv[1];
	int iterations = atoi(argv[2]);
	assert(iterations <= MAX_TRIALS);
	int nblocks = atoi(argv[3]);
	int nthreads = atoi(argv[4]);
	int io_size = pageSize;
    if (argc > 5)
        io_size = atoi(argv[5]) * 1024;
    
	fprintf(stderr, "\tfilename %s: iterations %d, blocks %d, threads %d, io_size %d\n", filename, iterations, nblocks, nthreads, io_size);

	test_read_latency_bandwidth(filename, nblocks, nthreads, iterations, io_size);

    
}
