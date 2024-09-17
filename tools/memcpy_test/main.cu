#include <stddef.h>
#include <iostream>

struct GpuTimer
{
      cudaEvent_t start;
      cudaEvent_t stop;

      GpuTimer() {
            cudaEventCreate(&start);
            cudaEventCreate(&stop);
      }

      ~GpuTimer() {
            cudaEventDestroy(start);
            cudaEventDestroy(stop);
      }

      void Start() {
            cudaEventRecord(start, 0);
      }

      void Stop() {
            cudaEventRecord(stop, 0);
      }

      float Elapsed() {
            float elapsed;
            cudaEventSynchronize(stop);
            cudaEventElapsedTime(&elapsed, start, stop);
            return elapsed;
      }
};


#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

#include <cooperative_groups/memcpy_async.h>

__forceinline__ __device__ int
my_lane_id() {
    int lane_id = threadIdx.x & 0x1f;
    return lane_id;
}

__forceinline__ __device__
void warp_memcpy_4kB(void *dest_, const void *src_) {
    uint64_t *dest = (uint64_t *)dest_;
    const uint64_t *src = (const uint64_t *)src_;
    int nr_participant = 32;
    int participant_id = my_lane_id();
    for (size_t i = participant_id;
            i < 256;
            i += nr_participant * 16) {
        dest[i] = src[i];
        dest[i + nr_participant * 1] = src[i + nr_participant * 1];
        dest[i + nr_participant * 2] = src[i + nr_participant * 2];
        dest[i + nr_participant * 3] = src[i + nr_participant * 3];
        dest[i + nr_participant * 4] = src[i + nr_participant * 4];
        dest[i + nr_participant * 5] = src[i + nr_participant * 5];
        dest[i + nr_participant * 6] = src[i + nr_participant * 6];
        dest[i + nr_participant * 7] = src[i + nr_participant * 7];
        dest[i + nr_participant * 8] = src[i + nr_participant * 8];
        dest[i + nr_participant * 9] = src[i + nr_participant * 9];
        dest[i + nr_participant * 10] = src[i + nr_participant * 10];
        dest[i + nr_participant * 11] = src[i + nr_participant * 11];
        dest[i + nr_participant * 12] = src[i + nr_participant * 12];
        dest[i + nr_participant * 13] = src[i + nr_participant * 13];
        dest[i + nr_participant * 14] = src[i + nr_participant * 14];
        dest[i + nr_participant * 15] = src[i + nr_participant * 15];
    }
}

#define page_size 4096
static __global__ void
memcpy2(void *dest_, void *src_, size_t len) {
    uint8_t *dest = (uint8_t *)dest_;
    uint8_t *src = (uint8_t *)src_;
    //int page_size = 4096;





    size_t nr_block = gridDim.x;
    size_t block_id = blockIdx.x;
    size_t nr_thread_per_block = blockDim.x;
    size_t nr_warp__per_block = nr_thread_per_block / 32;
    size_t warp_id__in_block = threadIdx.x / 32;
    int tid = blockIdx.x * blockDim.x + threadIdx.x;

    assert(0 < nr_warp__per_block); // Every warp must hold 32 threads

    if (nr_warp__per_block <= warp_id__in_block)
        // drop less-32-thread warp
        return;

    __syncwarp();
    size_t nr_thread_in_the_warp = __popc(__activemask());
    assert(nr_thread_in_the_warp == 32);



    size_t begin = 0;
    size_t exclusive_end = len / page_size;


    size_t nr_page = exclusive_end - begin;
    size_t nr_page__per_block = nr_page / nr_block;
    if (nr_page % nr_block != 0)
        nr_page__per_block++;

    size_t begin__block = begin + block_id * nr_page__per_block;
    size_t exclusive_end__block = begin__block + nr_page__per_block;
    if (exclusive_end <= begin__block)
        return;

    if (exclusive_end < exclusive_end__block)
        exclusive_end__block = exclusive_end;

    size_t nr_page__block = exclusive_end__block - begin__block;
    size_t nr_page__per_warp = nr_page__block / nr_warp__per_block;
    if (nr_page__block % nr_warp__per_block != 0)
        nr_page__per_warp++;

    size_t begin__warp = begin__block + warp_id__in_block * nr_page__per_warp;
    size_t exclusive_end__warp = begin__warp + nr_page__per_warp;
    if (exclusive_end__block <= begin__warp)
        return;

    if (exclusive_end__block < exclusive_end__warp)
        exclusive_end__warp = exclusive_end__block;

    src += page_size * begin__warp;
    dest += page_size * begin__warp;
    for (size_t page_id = begin__warp; page_id < exclusive_end__warp; page_id++) {
        warp_memcpy_4kB(dest, src);
        src += page_size;
        dest += page_size;
    }
}

static __global__ void
memcpy1(void *dest, void *src, size_t len) {
    auto block = cooperative_groups::this_thread_block();
    cooperative_groups::memcpy_async(block, dest, src, len);
    cooperative_groups::wait(block); // Joins all threads, waits for all copies to complete

    //uint32_t participating_mask = __active_mask();

}

#define kernel_time(code) ({ \
        GpuTimer gputimer; \
        gputimer.Start(); \
        {code} \
        gputimer.Stop(); \
        cudaDeviceSynchronize(); \
        gputimer.Elapsed(); \
})


static void
dev_memcpy1(void *buf1, void *buf2, size_t len) {
    memcpy1<<<2, 512>>>(buf1, buf2, len);
}
static void
dev_memcpy2(void *buf1, void *buf2, size_t len) {
    memcpy2<<<108, 32>>>(buf1, buf2, len);
}
static void
dev_memcpy3(void *buf1, void *buf2, size_t len) {
    memcpy3<<<108, 32>>>(buf1, buf2, len);
}
int
main () {
    size_t virtual_space_size = 16 * (1ull << 30)/*GB*/;
    void *buf1, *buf2;
    gpuErrchk(cudaMallocManaged(&buf1, virtual_space_size));
    gpuErrchk(cudaMallocManaged(&buf2, virtual_space_size));

    float time, bw;

    time = kernel_time({
            cudaMemcpy(buf1, buf2, virtual_space_size, cudaMemcpyDeviceToDevice);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;

    time = kernel_time({
            cudaMemcpy(buf2, buf1, virtual_space_size, cudaMemcpyDeviceToDevice);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;

    time = kernel_time({
            cudaMemcpy(buf2, buf1, virtual_space_size, cudaMemcpyDeviceToDevice);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;

    time = kernel_time({
            cudaMemcpy(buf2, buf1, virtual_space_size, cudaMemcpyDeviceToDevice);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;

    time = kernel_time({
            dev_memcpy1(buf2, buf1, virtual_space_size);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;

    time = kernel_time({
            dev_memcpy1(buf2, buf1, virtual_space_size);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;

    time = kernel_time({
            dev_memcpy2(buf2, buf1, virtual_space_size);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;
    time = kernel_time({
            dev_memcpy3(buf2, buf1, virtual_space_size);
            });
    bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    std::cout << "time:" << time << "ms " << "bw:" << bw << "GB per s" << std::endl;

    //GpuTimer gpu_timer;
    //gpu_timer.Start();
    //cudaMemcpy(buf1, buf2, virtual_space_size, cudaMemcpyDeviceToDevice);
    //gpu_timer.Stop();
    //time = gpu_timer.Elapsed();
    //bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    //std::cout << "bw:" << bw << "GB per s" << std::endl;
    //cudaDeviceSynchronize();

    //GpuTimer gpu_timer1;
    //gpu_timer1.Start();
    //memcpy1<<<1, 32>>>(buf1, buf2, virtual_space_size);
    //gpu_timer1.Stop();
    //time = gpu_timer1.Elapsed();
    //bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    //std::cout << "bw:" << bw << "GB per s" << std::endl;
    //cudaDeviceSynchronize();

    //GpuTimer gpu_timer2;
    //gpu_timer2.Start();
    //cudaMemcpy(buf1, buf2, virtual_space_size, cudaMemcpyDeviceToDevice);
    //gpu_timer2.Stop();
    //time = gpu_timer2.Elapsed();
    //bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    //std::cout << "bw:" << bw << "GB per s" << std::endl;
    //cudaDeviceSynchronize();


    //GpuTimer gpu_timer2;
    //gpu_timer2.Start();
    //cudaMemcpy(buf1, buf2, virtual_space_size, cudaMemcpyDeviceToDevice);
    //gpu_timer2.Stop();
    //time = gpu_timer2.Elapsed();
    //bw = ((float) 2 * virtual_space_size * 1000) / (time * (1ull << 30));
    //std::cout << "bw:" << bw << "GB per s" << std::endl;
    //cudaDeviceSynchronize();

    return 0;
}
