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

// Includes
#include <fcntl.h>
#include <assert.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <iostream>
#include <cstring>
#include <cuda.h>
#include <cufile.h>
#include "cufile_sample_utils.h"
#include <iomanip> // 用于控制输出格式  
// includes, project
//#include "helper_cuda_drvapi.h"
//#include "helper_functions.h"

// includes, CUDA
#include <builtin_types.h>
#include <cuda.h>
#include <vector>
#include <thread>
#include <chrono>  



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

static size_t round_up(size_t x, size_t y)
{
    return ((x + y - 1) / y) * y;
}



using namespace std;

typedef struct cfg {
        int gpu;
        CUfileHandle_t cf_handle_A;
        CUfileHandle_t cf_handle_B;

} cfg_t;
#define MAX_N_THREADS 700
pthread_t threads[MAX_N_THREADS];
const char *TESTFILEA, *TESTFILEB;

#ifdef __cplusplus
extern "C" {
extern void vectorAdd(const float *A, const float *B, float *C,
                          int numElements);
}
#endif



static void* thread_vector_addtion(void* arg)
{
       
        void* d_A = NULL;
        void* d_B = NULL;
        void* d_C = NULL;
        float *h_A;
        float *h_B;
        float *h_C;
        CUfileError_t status;
        int ret;
        // printf("Vector Addition (Driver API), pid = %ld\n", std::this_thread::get_id());
        int N = 28835840;
        size_t  size =  N * sizeof(float);
        // printf("total number of elements in each vector :%d \n", N);
        printf("size of each sysmem vector in bytes :%ld \n", size);

        cfg_t *cfg = (cfg_t *)arg;
    
        
        // Initialize
        check_cudaruntimecall(cudaSetDevice(cfg->gpu));


        check_cudaruntimecall(cudaMalloc(&d_A, size));
	check_cudaruntimecall(cudaMalloc(&d_B, size));
	check_cudaruntimecall(cudaMalloc(&d_C, size));

        //start = clock();
        cudaEvent_t     start, stop;
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
        cudaEventRecord(start, 0) ;
        auto start2 = std::chrono::high_resolution_clock::now(); 
        // std::cout << "registering device memory(d_A) of size :" << size << std::endl;
        // registers device memory
        status = cuFileBufRegister((void*)d_A, 4096, 0);
        if (status.err != CU_FILE_SUCCESS) {
                ret = -1;
                std::cerr << "buffer register A failed:"
                        << cuFileGetErrorString(status) << std::endl;
                exit(EXIT_FAILURE);
        }

        // std::cout << "registering device memory(d_B) of size :" << size << std::endl;
        // registers device memory
        status = cuFileBufRegister((void*)d_B, 4096, 0);
        if (status.err != CU_FILE_SUCCESS) {
                ret = -1;
                std::cerr << "buffer register B failed:"
                        << cuFileGetErrorString(status) << std::endl;
                exit(EXIT_FAILURE);
        }

        // std::cout << "reading to device memory d_A from file:" << TESTFILEA << std::endl;

        // reads device memory contents A from file A for size bytes
        ret = cuFileRead(cfg->cf_handle_A, (void*)d_A, 4096, 0, 0);
        if (ret < 0) {
                if (IS_CUFILE_ERR(ret))
                        std::cerr << "read failed : "
                                << cuFileGetErrorString(ret) << std::endl;
                else
                        std::cerr << "read failed : "
                                << cuFileGetErrorString(errno) << std::endl;
                exit(1);
        } else {
                // std::cout << "read bytes to d_A:" << ret << std::endl;
                ret = 0;
        }


        // std::cout << "reading to device memory d_B from file:" << TESTFILEB << std::endl;

        // reads device memory contents B from file B for size bytes
        // offset
        ret = cuFileRead(cfg->cf_handle_B, (void*)d_B, 4096, 0, 0);
        if (ret < 0) {
                if (IS_CUFILE_ERR(ret))
                        std::cerr << "read failed : "
                                << cuFileGetErrorString(ret) << std::endl;
                else
                        std::cerr << "read failed : "
                                << cuFileGetErrorString(errno) << std::endl;
                exit(1);
        } else {
                // std::cout << "read bytes to d_B :" << ret << std::endl;
                ret = 0;
        }
        check_cudaruntimecall(cudaStreamSynchronize(0));
        auto end2 = std::chrono::high_resolution_clock::now();  
        // end = clock();
        auto elapsed2 = std::chrono::duration_cast<std::chrono::microseconds>(end2 - start2);
        double rtime = static_cast<double>(elapsed2.count());
        printf("Thread time is %.3f us\n",rtime);
        // std::cout << "Thread elapsed time: " << elapsed2.count() << "us\n"; 
        cudaEventRecord(stop, 0);

        float   elapsedTime;
        cudaEventElapsedTime(&elapsedTime,start, stop);
        // printf( "Time :  %3.1f ms\n", elapsedTime );

        // printf("Total time : %.3f us\n", (double)(end - start) / (double) 1000);
        
      
        return NULL;


}

// Host code
int main(int argc, char **argv)
{
        int fdA=-1, fdB=-1, ret;
        CUfileError_t status;
        CUfileDescr_t cf_descr;
        CUfileHandle_t cf_handle_A,cf_handle_B;
      


        if(argc < 5) {
                std::cerr << argv[0] << " gpuId nthreads <filepathA>  <filepathB> "<< std::endl;
                exit(EXIT_FAILURE);
        }
        int gpuId = atoi(argv[1]);
        int nthreads = atoi(argv[2]);
        TESTFILEA = argv[3];
        TESTFILEB = argv[4];

        status = cuFileDriverOpen();
        if (status.err != CU_FILE_SUCCESS) {
                std::cerr << "cufile driver open error: "
                        << cuFileGetErrorString(status) << std::endl;
                exit(EXIT_FAILURE);
        }

        std::cout << "opening file " << TESTFILEA << std::endl;
        std::cout << "opening file " << TESTFILEB << std::endl;

        // opens file A to write
        ret = open(TESTFILEA, O_CREAT | O_RDWR | O_DIRECT, 0664);
        if (ret < 0) {
                std::cerr << "file open error:"
                        << cuFileGetErrorString(errno) << std::endl;
                exit(EXIT_FAILURE);
        }
        fdA = ret;

        // opens file B to write
        ret = open(TESTFILEB, O_CREAT | O_RDWR | O_DIRECT, 0664);
        if (ret < 0) {
                std::cerr << "file open error:"
                        << cuFileGetErrorString(errno) << std::endl;
                exit(EXIT_FAILURE);
        }
        fdB = ret;


        memset((void *)&cf_descr, 0, sizeof(CUfileDescr_t));
        cf_descr.handle.fd = fdA;
        cf_descr.type = CU_FILE_HANDLE_TYPE_OPAQUE_FD;
        status = cuFileHandleRegister(&cf_handle_A, &cf_descr);
        if (status.err != CU_FILE_SUCCESS) {
                std::cerr << "file register error:"
                        << cuFileGetErrorString(status) << std::endl;
                close(fdA);
                exit(EXIT_FAILURE);
        }


        memset((void *)&cf_descr, 0, sizeof(CUfileDescr_t));
        cf_descr.handle.fd = fdB;
        cf_descr.type = CU_FILE_HANDLE_TYPE_OPAQUE_FD;
        status = cuFileHandleRegister(&cf_handle_B, &cf_descr);
        if (status.err != CU_FILE_SUCCESS) {
                std::cerr << "file register error:"
                        << cuFileGetErrorString(status) << std::endl;
                close(fdA);
                close(fdB);
                exit(EXIT_FAILURE);
        }

        for (int i = 0; i < nthreads; i++)
        {
                cfg_t cfg;
                pthread_t thread;
                cfg.gpu = gpuId;
                cfg.cf_handle_A = cf_handle_A;
                cfg.cf_handle_B = cf_handle_B;
                pthread_create(&thread, NULL, &thread_vector_addtion, &cfg);
                threads[i] = thread;
        }
        for (int i = 0; i < nthreads; i++)
        {
                pthread_join(threads[i], NULL);
        }
        


        // deregister the device memory
        status = cuFileDriverClose();
        if (status.err != CU_FILE_SUCCESS) {
                std::cerr << "cuFileDriverClose failed:"
                        << cuFileGetErrorString(status) << std::endl;
        }
        close(fdA);
        close(fdB);

        return 0;


}
