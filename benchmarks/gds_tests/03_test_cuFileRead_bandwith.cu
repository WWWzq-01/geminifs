/*
 * Copyright 2020 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */

/* Vector addition: C = A + B.
 *
 * This sample replaces the device allocation in the vectorAddDrvsample with
 * cuMemMap-ed allocations.  This sample demonstrates that the cuMemMap api
 * allows the user to specify the physical properties of their memory while
 * retaining the contiguos nature of their access, thus not requiring a change
 * in their program structure.
 *
 */

# include <fcntl.h>
#include <assert.h>
#include <unistd.h>


#include <cstdlib>
#include <cstring>
#include <iostream>

#include <cuda_runtime.h>
#include <chrono>  

//include this header file
#include "cufile.h"

#include "cufile_sample_utils.h"

#include <chrono>  

__global__ void warmup() {}




// CUDA Driver API errors
static const char *_cudaGetErrorEnum(CUresult error) {
  static char unknown[] = "<unknown>";
  const char *ret = NULL;
  cuGetErrorName(error, &ret);
  return ret ? ret : unknown;
}


template <typename T>
void check(T result, char const *const func, const char *const file,
           int const line) {
  if (result) {
    fprintf(stderr, "CUDA error at %s:%d code=%d(%s) \"%s\" \n", file, line,
            static_cast<unsigned int>(result), _cudaGetErrorEnum(result), func);
    exit(EXIT_FAILURE);
  }
}

#define checkCudaErrors(val) check((val), #val, __FILE__, __LINE__)



using namespace std;


const char *TESTFILE;
#define MAX_READ_IO_NUM (2000000)

u_int64_t file_size = 1LL << 33; // 8GBf
u_int64_t IO_SIZE = 4 * 1024;

// Host code
int main(int argc, char **argv)
{
        // GPU预热
        warmup<<<1, 1>>>();
        cudaDeviceSynchronize();

        int fd=-1, ret;
        CUfileError_t status;
        CUfileDescr_t cf_descr;
        CUfileHandle_t cf_handle;


        if(argc < 5) {
                std::cerr << argv[0] << " Usage: GPUId <Filepath> O_DIRECT iterations IO_Size(default: 4096)"<< std::endl;
                exit(EXIT_FAILURE);
        }
        int gpuId = atoi(argv[1]);
        TESTFILE = argv[2];
        int O_Flag = atoi(argv[3]);
        int iterations = atoi(argv[4]);
        if (iterations > MAX_READ_IO_NUM)
        {
                std::cerr << "Error: iterations exceed maximum allowed value (" << MAX_READ_IO_NUM << ")." << std::endl;
                return EXIT_FAILURE;
        }
        
        uint64_t io_size = IO_SIZE;  
        if (argc > 5) {
                io_size = atoi(argv[5]) * 1024;
        }
        
        check_cudaruntimecall(cudaSetDevice(gpuId));

        status = cuFileDriverOpen();
        if (status.err != CU_FILE_SUCCESS) {
                std::cerr << "cufile driver open error: "
                        << cuFileGetErrorString(status) << std::endl;
                exit(EXIT_FAILURE);
        }
        printf("gpuid: %d, O_Flag: %d, iterations: %d, io_size: %d\n", gpuId, O_Flag, iterations, io_size);
        // opens file 
        if(O_Flag)
                ret = open(TESTFILE, O_CREAT | O_RDWR | O_DIRECT, 0664);       
        else
                ret = open(TESTFILE, O_CREAT | O_RDWR, 0644);
        if (ret < 0) {
                std::cerr << "file open error:"
                        << cuFileGetErrorString(errno) << std::endl;
                exit(EXIT_FAILURE);
        }
        
        fd = ret;

        memset((void *)&cf_descr, 0, sizeof(CUfileDescr_t));
        cf_descr.handle.fd = fd;
        cf_descr.type = CU_FILE_HANDLE_TYPE_OPAQUE_FD;

        // Register file handle
        status = cuFileHandleRegister(&cf_handle, &cf_descr);
        if (status.err != CU_FILE_SUCCESS) {
                std::cerr << "file register error:"
                        << cuFileGetErrorString(status) << std::endl;
                close(fd);
                exit(EXIT_FAILURE);
        }
       
        cudaEvent_t     start_cuda, stop_cuda;
        cudaEventCreate(&start_cuda);
        cudaEventCreate(&stop_cuda);
        for (int i = 0; i < iterations; i++)
        {        
                void* devPtr = NULL;

                check_cudaruntimecall(cudaMalloc(&devPtr, io_size));
                // special case for holes
                check_cudaruntimecall(cudaMemset(devPtr, 0, io_size));
                check_cudaruntimecall(cudaStreamSynchronize(0));

                // auto start = std::chrono::high_resolution_clock::now();
                cudaEventRecord(start_cuda, 0) ;

                ret = cuFileRead(cf_handle, devPtr, io_size, 0 , 0);
                if (ret < 0) {
                        if (IS_CUFILE_ERR(ret))
                                std::cerr << "read failed : " << cuFileGetErrorString(ret) << std::endl;
                        else
                                std::cerr << "read failed : " << cuFileGetErrorString(errno) << std::endl;
                        cuFileHandleDeregister(cf_handle);
                        close(fd);
                        check_cudaruntimecall(cudaFree(devPtr));
                        return -1;
                }

                float cudaTime;
                cudaEventRecord(stop_cuda, 0);
                cudaEventSynchronize(stop_cuda);        //计时这里的同步是必须的，否则时间会非常短
                cudaEventElapsedTime(&cudaTime, start_cuda, stop_cuda);
                // std::cout << "cudaTime: " << cudaTime*1000  << " us"<< std::endl;
                // std::cout << "Bandwidth: " << (io_size *1000) / (cudaTime * 1024 * 1024)<< " MB/s" << std::endl;
                printf("Latency: %.3f us, Bandwidth: %.3f MB/s\n", cudaTime * 1000, ((double)io_size *1000) / (cudaTime * 1024 * 1024));

            
                // cudaDeviceSynchronize();
                // auto end = std::chrono::high_resolution_clock::now();
                // auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

                // std::chrono::duration<double> elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(end-start); // CPU计时需要增加同步
                // std::cout << "elapsed_cpp: "<< elapsed.count() << "us" <<std::endl;        // 转为us会降低精度
                // std::cout << "Bandwidth: " << (io_size *1000 * 1000) / ((double)elapsed.count() * 1024 * 1024)<< " MB/s" << std::endl;

                // cudaEventDestroy(start_cuda);
                // cudaEventDestroy(stop_cuda);
	   
                if(devPtr)
                        check_cudaruntimecall(cudaFree(devPtr));
        }
        // double avg_time = total_time / iterations;
        // printf("Avg bandwidth:%f MB/s\n", io_size / avg_time / 1024 / 1024);
        cuFileHandleDeregister(cf_handle);
        close(fd);

        return 0;


}
