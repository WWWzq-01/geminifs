#ifndef GEMINIFS_INTERNAL_H
#define GEMINIFS_INTERNAL_H
#include "geminifs_api.cuh"

#include <cassert>
#include <iostream>
#include <cuda/semaphore>

__forceinline__ __device__ int
my_lane_id() {
    int lane_id = threadIdx.x & 0x1f;
    return lane_id;
}

__forceinline__ __device__
void warp_memcpy_4kB(void *dest_, const void *src_, uint32_t participating_mask) {
    uint64_t *dest = (uint64_t *)dest_;
    const uint64_t *src = (const uint64_t *)src_;
    int nr_participant = __popc(participating_mask);
    int lane = my_lane_id();
    int participant_id = __popc(participating_mask >> (32 - lane));
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

using CachePageId = size_t;
using FilePageId = size_t;
enum CachePage_State {
    CACHEPAGE_INVALID,
    CACHEPAGE_CLEAN,
    CACHEPAGE_DIRTY,
};

class CachePage {
public:
    __device__
    CachePage(int page_size_, void * const buf_, int never_evicted_): 
        page_size(page_size_),
        buf(buf_),
        never_evicted(never_evicted_) { }

    __device__ virtual
    ~CachePage() { }

    __forceinline__ __device__ void
    write_back__no_lock(void *info1, void *info2, void *info3) {
        if (this->state == CACHEPAGE_DIRTY) {
            this->__write_back(this->content_of, info1, info2, info3);
            this->state = CACHEPAGE_CLEAN;
            __threadfence();
        }
    }
    __forceinline__ __device__ void
    read_in__no_lock(void *info1, void *info2, void *info3,
            int read_dummy/* For overwrite */) {
        if ((this->content_of != this->assigned_to) || this->state == CACHEPAGE_INVALID) {
            this->write_back__no_lock(info1, info2, info3);

            // Here, the state is INVALID or CLEAN

            if (!read_dummy)
                this->__read_in(this->assigned_to, info1, info2, info3);
            this->content_of = this->assigned_to;
            this->state = CACHEPAGE_CLEAN;
            __threadfence();
        }
    }

    __forceinline__ __device__ void
    sync(void *info1, void *info2, void *info3) {
        this->lock.acquire();
        this->write_back__no_lock(info1, info2, info3);
        this->lock.release();
    }

    __forceinline__ __device__ void
    set_dirty() {
        this->lock.acquire();
        this->state = CACHEPAGE_DIRTY;
        this->lock.release();
    }

    CachePageId cachepage_id;
    FilePageId content_of; // the filepage to which the data belongs
    FilePageId assigned_to; // the filepage specified by the pagecache mechanism
    enum CachePage_State state;
    cuda::binary_semaphore<cuda::thread_scope_device> lock;

    void *buf;
    const int page_size;
    const int never_evicted;
private:
    virtual __device__ void __write_back(FilePageId filepage_id, void *info1, void *info2, void *info3) = 0;
    virtual __device__ void __read_in(FilePageId filepage_id, void *info1, void *info2, void *info3) = 0;
};

class PageCache {
public:
    __device__
    PageCache() { }

    __device__ virtual
    ~PageCache() { }

    virtual __device__ size_t
    acquire_pages__for_warp(
            const FilePageId *filepage_ids,
            CachePageId *cachepage_ids,
            size_t nr_acquire_pages,
            int will_overwrite/* no need to read in */) = 0;

    virtual __device__ void
    set_page_dirty__for_warp(FilePageId filepage_id, CachePageId cachepage_id) = 0;

    virtual __device__ void
    release_page__for_warp(FilePageId filepage_id) = 0;

    virtual __device__ void
    sync() = 0;

    virtual __device__ uint8_t *
    get_raw_page_buf(FilePageId filepage_id, CachePageId cachepage_id) = 0;

    virtual __device__ int
    get_page_bit_num() = 0;

    virtual __device__ void
    __set_filepage_id_base(FilePageId filepage_id_base) = 0;
};


extern PageCache *
__internal__get_pagecache(
        uint64_t pagecache_capacity,
        int page_size,
        uint64_t size_of_virtual_space,
        CachePage *pages[],
        int sync_parallelism,
        void *info1, void *info2, void *info3);

extern PageCache *
__internal__get_batched_pagecache(
        int page_size,
        PageCache **pagecaches,
        int pagecache_batching_size,
        int nr_pages__per_pagecache,
        size_t virtual_space_size);

extern void
__internal__drop_pagecache(PageCache *);

template <typename T>
__global__ void
__run_device_lambda(T lambda) {
    lambda();
}

#define RUN_ON_DEVICE__MULTI_THREAD(CODE_BLOCK, nr_thread) { \
    __run_device_lambda<<<1, nr_thread>>>([=] __device__ () { \
        CODE_BLOCK \
    }); \
    cudaDeviceSynchronize(); \
}

#define RUN_ON_DEVICE(CODE_BLOCK) RUN_ON_DEVICE__MULTI_THREAD(CODE_BLOCK, 1)

#endif
