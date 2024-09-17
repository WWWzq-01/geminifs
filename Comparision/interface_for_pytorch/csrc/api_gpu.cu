#include "api_gpu.cuh"


int global_device=0;

inline void __checkCudaErrors(cudaError err, const char *file, const int line)
{
	if (cudaSuccess != err)
	{
		fprintf(stderr, "%s(%i) : CUDA Runtime API error %d: %s.\n", file, line, (int) err, cudaGetErrorString(err));
		exit(-1);
	}
}
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

__global__ void read(char* filename, size_t *offset, size_t *size, char* buffer)
{
	__shared__ uchar* scratch;
	__shared__ int fd;
	BEGIN_SINGLE_THREAD 
	scratch = (uchar*) malloc((*size) + 1);
	GPU_ASSERT(scratch != NULL);
	END_SINGLE_THREAD
	fd = 0;
	fd = gopen(filename, O_GRDONLY | O_DIRECT);
	if (fd < 0)
			ERROR("Failed to open file");

	if (*size != gread(fd, *offset, *size, scratch))
	{
		assert(NULL);
	}
	__syncthreads();

	// copy to buffer
	for (size_t i = threadIdx.x; i < *size; i += blockDim.x) {
        buffer[i] = scratch[i];
    }
	gclose(fd);
}


__global__ void write(char* filename, size_t *offset, size_t *size, char *data)
{
   
    __shared__ int fd;
    fd = 0;
    fd = gopen(filename, O_GRDWR | O_GCREAT | O_GWRONCE);
    if (fd < 0)
        ERROR("Failed to open file");
   
    size_t bytes_write = gwrite(fd, *offset, *size, (uchar*)data);
    if(bytes_write != *size)
        ERROR("Failed to write data");
    if(gclose(fd) < 0)
        ERROR("Failed to close file");
}


void gpu_read(char* filename, size_t offset, size_t size, char *buffer)
{
	DeviceData device_data = copy_data_to_device(filename, offset, size);
    volatile GPUGlobals* gpuGlobals;
	initializer(&gpuGlobals);
	// TODO:
	read<<<1,1,0,gpuGlobals->streamMgr->kernelStream>>>(device_data.d_filename, device_data.d_offset, device_data.d_size, buffer);
	run_gpufs_handler(gpuGlobals, global_device);
	cudaError_t error = cudaDeviceSynchronize();
	//Check for errors and failed asserts in asynchronous kernel launch.
	if (error != cudaSuccess)
	{
		printf("Device failed, CUDA error message is: %s\n\n",
		cudaGetErrorString(error));
	}

	fprintf(stderr, "\n");
	delete gpuGlobals;

	// cudaDeviceReset();
}

void gpu_write(char* filename, size_t offset, size_t size, char *d_data)
{
   	DeviceData device_data = copy_data_to_device(filename, offset, size);
    volatile GPUGlobals* gpuGlobals;
	initializer(&gpuGlobals);
    // TODO
	write<<<1,1,0,gpuGlobals->streamMgr->kernelStream>>>(device_data.d_filename, device_data.d_offset, device_data.d_size, d_data);
	run_gpufs_handler(gpuGlobals, global_device);
	cudaError_t error = cudaDeviceSynchronize();
	if (error != cudaSuccess)
	{
		printf("Device failed, CUDA error message is: %s\n\n",
		cudaGetErrorString(error));
	}

	fprintf(stderr, "\n");
	delete gpuGlobals;

	// cudaDeviceReset();

}


// int main(int argc, char** argv)
// {
// 	int device = global_device;
// 	char* gpudev = getenv("GPUDEVICE");
// 	if (gpudev != NULL)
// 		device = atoi(gpudev);

// 	CUDA_SAFE_CALL(cudaSetDevice(device));

// 	cudaDeviceProp deviceProp;
// 	CUDA_SAFE_CALL(cudaGetDeviceProperties(&deviceProp, device));
// 	printf("Running on device %d: \"%s\"\n", device, deviceProp.name);

// 	int trials = 1;
// 	int nblocks = 1;
// 	int nthreads = 1;
// 	char *read_filename = "test.txt";
// 	char *write_filename = "write_test.txt";
//     size_t offset = 0;
//     char *h_data = "222";
//     size_t size = 3;
// 	char* d_data =copy_string_to_device(h_data);

// 	gpu_write(write_filename, offset, size, d_data);
// 	// char* d_buffer = nullptr;
// 	// char* h_buffer = (char*)malloc(4);

// 	// CUDA_SAFE_CALL(cudaMalloc(&d_buffer,3+1));
// 	// cudaMemset(d_buffer, 1, 3);
// 	// // gpu_read(read_filename, offset, size, d_buffer);

// 	// CUDA_SAFE_CALL(cudaMemcpy(h_buffer, d_buffer, 4, cudaMemcpyDeviceToHost));
// 	// printf("Read: %s\n", h_buffer);
// 	return 0;
// }