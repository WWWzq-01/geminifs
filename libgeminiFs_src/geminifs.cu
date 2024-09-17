#include <cuda/atomic>
#include <cuda/semaphore>

#include <cooperative_groups.h>

#include "geminifs_api.h"
#include "geminifs_api.cuh"
#include "geminifs_internal.cuh"

static int
one_nr__of__binary_int(unsigned long long i) {
  int count = 0;
  while (i != 0) {
    if ((i & 1) == 1)
      count++;
    i = i >> 1;
  }
  return count;
}

#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
static inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

#define cdpErrchk(ans) { cdpAssert((ans), __FILE__, __LINE__); }
static __device__ void cdpAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      printf("GPU kernel assert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) assert(0);
   }
}

struct MyLinklistNode {
    MyLinklistNode *pre, *suc;
};
template <typename T>
struct MyLinklistNodeD: public MyLinklistNode {
    T v;
};
class MyLinklist {
public:
    __device__ MyLinklist() {
        this->head.suc = &(this->tail);
        this->tail.pre = &(this->head);
    }
    __inline__ __device__ void
    push(MyLinklistNode *new_node) {
        this->insert_after(&(this->head), new_node);
    }
    __inline__ __device__ void
    enqueue(MyLinklistNode *new_node) {
        this->insert_after(this->tail.pre, new_node);
    }
    __inline__ __device__ MyLinklistNode *
    pop() {
        auto *ret_node = this->head.suc;
        if (ret_node != &(this->tail)) {
            this->detach_node(ret_node);
            return ret_node;
        }
        assert(0);
        return ret_node;
    }
    __inline__ __device__ void
    detach_node(MyLinklistNode *n) {
        (n->pre)->suc = n->suc;
        (n->suc)->pre = n->pre;
    }
private:
    __forceinline__ __device__ void
    insert_after(MyLinklistNode *insert_point, MyLinklistNode *n) {
        n->pre = insert_point;
        n->suc = insert_point->suc;
        insert_point->suc->pre = n;
        insert_point->suc = n;
    }
    MyLinklistNode head, tail;
};


class CachePage_WithoutBacking: public CachePage {
public:
    __device__
    CachePage_WithoutBacking(int page_size, void * const buf_): CachePage(page_size, buf_, 1) { }
private:
    __device__ void __write_back(FilePageId filepage_id, void *info1, void *info2, void *info3) { }
    __device__ void __read_in(FilePageId filepage_id, void *info1, void *info2, void *info3) { }
};




template <typename T>
static __global__ void
__sync__helper(T *pagecache) {
    pagecache->__sync__for_block();
}

class PageCacheImpl__info1 {
public:
    FilePageId filepage_id;
    cuda::counting_semaphore<cuda::thread_scope_device> wait_for_evicting;
    int nr_waiting;
};

class PageCacheImpl: public PageCache {
public:
    __device__ PageCacheImpl(uint64_t pagecache_capacity,
            int page_size,
            uint64_t size_of_virtual_space,
            CachePage *pages[],
            int sync_parallelism,
            void *info1, void *info2, void *info3,
            MyLinklistNode *map1[],
            CachePageId *map2,
            MyLinklistNode *map3[]):
        filepages__waiting_for_evicting(map1),
        nr_waiting(0),
        filepage__to__cachepage(map2),
        zero_reffed_filepages(map3),
        nr_zero_pages(0)
    {
        this->sync_parallelism = sync_parallelism;
        this->info1 = info1;
        this->info2 = info2;
        this->info3 = info3;

        this->pagecache_lock.release();

        uint64_t nr_page = pagecache_capacity / page_size;
        uint64_t nr_file_page = size_of_virtual_space / page_size;

        this->filepage_id_base = 0;
        this->filepage_id_exclusive_end = this->filepage_id_base + nr_file_page;

        for (FilePageId filepage_id = this->filepage_id_base;
                filepage_id < this->filepage_id_exclusive_end;
                filepage_id++) {
            this->filepages__waiting_for_evicting[filepage_id] = nullptr;
            this->filepage__to__cachepage[filepage_id] = -1;
            this->zero_reffed_filepages[filepage_id] = nullptr;
        }

        this->page_size = page_size;
        this->nr_page = nr_page;
        this->nr_file_page = nr_file_page;

        this->pages = pages;
        this->pages_ref = (uint64_t *)malloc(sizeof(uint64_t) * this->nr_page);

        for (CachePageId cachepage_id = 0; cachepage_id < nr_page; cachepage_id++) {
            FilePageId filepage_id = this->filepage_id_base + (this->nr_file_page - 1 - cachepage_id);
            auto *page = this->pages[cachepage_id];
            page->cachepage_id = cachepage_id;
            page->content_of = filepage_id;
            page->assigned_to = filepage_id;
            page->lock.release();
            if (page->never_evicted) {
                page->state = CACHEPAGE_CLEAN;
                this->pages_ref[cachepage_id] = 1; // the Ref Count is at lease 1, thus the page won't be evicted.
            } else {
                page->state = CACHEPAGE_INVALID;
                this->pages_ref[cachepage_id] = 0;
                this->__insert__zero_reffed_filepage(filepage_id);
            }
            this->__insert__filepage__mapping_to__cachepage(filepage_id, cachepage_id);
        }
        printf("Geminifs open OK\n");
    }

    __device__ ~PageCacheImpl() {
        assert(0);
        for (CachePageId cachepage_id = 0;
                cachepage_id < nr_page;
                cachepage_id++)
            delete this->pages[cachepage_id];

        delete this->pages_ref;
        delete this->pages;
    }

    __device__ size_t
    acquire_pages__for_warp(
            const FilePageId *filepage_ids,
            CachePageId *cachepage_ids,
            size_t nr_acquire_pages,
            int will_overwrite) override {
        size_t n;
        uint32_t participating_mask = 0xffffffff;
        uint32_t warp_leader = 0;
        int lane = my_lane_id();
        if (lane == warp_leader) {
            n = this->__acquire_page_for_warp_leader(filepage_ids, cachepage_ids, nr_acquire_pages, will_overwrite);
        } else {
            this->__acquire_page_for_warp_follower(warp_leader, will_overwrite);
        }
        n = __shfl_sync(participating_mask, n, warp_leader);
        return n;
    }

    __device__ void
    set_page_dirty__for_warp(FilePageId filepage_id, CachePageId cachepage_id) override {
        uint32_t warp_leader = 0;
        int lane = my_lane_id();
        if (lane == warp_leader)
            this->pages[cachepage_id]->set_dirty();
    }

    __device__ void
    release_page__for_warp(FilePageId filepage_id) override {
        uint32_t warp_leader = 0;
        int lane = my_lane_id();
        if (lane == warp_leader)
            this->__release_page_for_warp_leader(filepage_id);
    }

    __device__ void
    sync() override {
        __syncwarp();
        uint32_t mask = __activemask();
        mask = __match_any_sync(mask, (uint64_t)this);
        uint32_t warp_leader = __ffs(mask) - 1;
        int lane = my_lane_id();
        if (lane == warp_leader) {
            this->pagecache_lock.acquire();
            __sync__helper<<<this->sync_parallelism, 1>>>(this);
        }
    }

    __device__ void
    __sync__for_block() {
        if (threadIdx.x != 0)
            return;
        auto grid = cooperative_groups::this_grid();

        size_t nr_page__per_block = this->nr_page / blockDim.x;
        if (this->nr_page % blockDim.x != 0)
            nr_page__per_block++;

        size_t start_page_idx = blockIdx.x * nr_page__per_block;
        size_t end_page_idx_exclusive = start_page_idx + nr_page__per_block;
        if (this->nr_page <= start_page_idx)
            return;
        if (this->nr_page < end_page_idx_exclusive)
            end_page_idx_exclusive = this->nr_page;

        for (size_t i = start_page_idx; i < end_page_idx_exclusive; i++)
            this->pages[i]->sync(this->info1, this->info2, this->info3);

        grid.sync();
        if (blockIdx.x == 0)
            this->pagecache_lock.release();
    }

    __forceinline__ __device__ uint8_t *
    get_raw_page_buf(FilePageId filepage_id, CachePageId cachepage_id) override {
        return (uint8_t *)this->pages[cachepage_id]->buf;
    }

    __forceinline__ __device__ int
    get_page_bit_num() override {
        return __popc(this->page_size - 1);
    }

    __device__ void
    __set_filepage_id_base(FilePageId filepage_id_base) override {
        //printf("filepage_id_base [%llx]\n", filepage_id_base);
        this->filepage_id_base = filepage_id_base;
        this->filepage_id_exclusive_end = this->filepage_id_base + this->nr_file_page;
    }
private:

    __noinline__ /* warp converge needed */ __device__ void *
    shfl_ptr_in_warp(int warp_leader, void *p) {
        __syncwarp();
	    return (void *)__shfl_sync(0xffffffff, (uint64_t)p, warp_leader);
    }

    __forceinline__ __device__ void
    __acquire_page_for_warp_follower(int warp_leader, int will_overwrite) {
        FilePageId *prefetch_filepage_ids = (FilePageId *)this->shfl_ptr_in_warp(warp_leader, nullptr);
        CachePageId *prefetch_cachepage_ids = (CachePageId *)this->shfl_ptr_in_warp(warp_leader, nullptr);
        if (prefetch_cachepage_ids == nullptr)
            return;

        int lane = my_lane_id();
        FilePageId prefetch_filepage_id = prefetch_filepage_ids[lane];
        CachePageId prefetch_cachepage_id = prefetch_cachepage_ids[lane];

        if (prefetch_filepage_id != -1 && prefetch_cachepage_id != -1) {
            //printf("I'm follower[%d] filepage_id[%llx] cachepage_id[%llx]\n",
            //        lane, prefetch_filepage_id, prefetch_cachepage_id);
            __syncwarp();
            this->pages[prefetch_cachepage_id]->lock.acquire();
            this->pages[prefetch_cachepage_id]->read_in__no_lock(this->info1, this->info2, this->info3, will_overwrite ? 1 : 0);
            this->pages[prefetch_cachepage_id]->lock.release();
        } else {
            __syncwarp();
        }
    }

    __forceinline__ __device__ CachePageId
    __acquire_page_for_warp_leader(
            const FilePageId *filepage_ids,
            CachePageId *cachepage_ids,
            size_t nr_acquire_pages,
            int will_overwrite) {

        FilePageId filepage_id = filepage_ids[0];
        CachePageId ret;

        this->pagecache_lock.acquire();

        // Assertion 1: If there is any zero-reffed page, nobody is waiting for evicting.
        // Assertion 2: If someone is waiting for evicting, there is not zero-reffed page.
        // Assertion 3: If the ref count of a cachepage is greater than 0,
        //              all the transactions about that cachepage are about the same filepage.

        //printf("I acquire filepage[%llx]\n", filepage_id);

        ret = this->__get__cachepage_id(filepage_id);
        if (ret != -1) {
            //printf("I want filepage[%llx], HIT! cachepage[%llx]\n", filepage_id, ret);
            // Page Hit!
            size_t cur_ref = (++(this->pages_ref[ret]));
            if (cur_ref == 1)
                this->__erase__zero_reffed_filepage(filepage_id);

            __threadfence();
            this->pagecache_lock.release();

            // Let followers go.
            this->shfl_ptr_in_warp(0, nullptr);
            this->shfl_ptr_in_warp(0, nullptr);

            this->pages[ret]->lock.acquire();
            this->pages[ret]->read_in__no_lock(this->info1, this->info2, this->info3, 0);
            this->pages[ret]->lock.release();

            cachepage_ids[0] = ret;
            return 1;
        }

        //printf("I want filepage[%llx], MISS!\n", filepage_id);

        // Miss
        // ret == -1

        FilePageId evicted_filepage_id = this->__pop__zero_reffed_filepage_id();
        if (evicted_filepage_id != -1) {
            // Here we find a zero-reffed page to be evicted

            ret = this->__get__cachepage_id(evicted_filepage_id);
            //printf("Here I find a filepage[%llx] cachepage[%llx] to be evicted\n", evicted_filepage_id, ret);
            ++(this->pages_ref[ret]);

            this->__erase__filepage__mapping(evicted_filepage_id);
            this->__insert__filepage__mapping_to__cachepage(filepage_id, ret);

            this->pages[ret]->assigned_to = filepage_id;

            __shared__ FilePageId prefetch_filepage_ids[32];
            __shared__ CachePageId prefetch_cachepage_ids[32];
            for (int follower = 1; follower < 32; follower++) {
                FilePageId prefetch_filepage_id;
                if (follower < nr_acquire_pages)
                    prefetch_filepage_id = filepage_ids[follower];
                else
                    prefetch_filepage_id = -1;

                if (prefetch_filepage_id != -1 &&
                        this->filepage_id_exclusive_end <= prefetch_filepage_id)
                    prefetch_filepage_id = -1;
                if (prefetch_filepage_id != -1 &&
                        -1 != this->__get__cachepage_id(prefetch_filepage_id)) {
                    /* Hit! It need not be prefetched */
                    prefetch_filepage_id = -1;
                }

                CachePageId prefetch_cachepage_id;
                do {
                    prefetch_cachepage_id = -1;
                    if (prefetch_filepage_id == -1)
                        break;
                    FilePageId evict_for_prefetch = this->__pop__zero_reffed_filepage_id();
                    if (evict_for_prefetch == -1)
                        break;
                    prefetch_cachepage_id = this->__get__cachepage_id(evict_for_prefetch);
                    ++(this->pages_ref[prefetch_cachepage_id]);
                    this->__erase__filepage__mapping(evict_for_prefetch);
                    this->__insert__filepage__mapping_to__cachepage(prefetch_filepage_id,
                            prefetch_cachepage_id);

                    this->pages[prefetch_cachepage_id]->assigned_to = prefetch_filepage_id;
                } while (0);

                prefetch_filepage_ids[follower] = prefetch_filepage_id;
                prefetch_cachepage_ids[follower] = prefetch_cachepage_id;
            }

            __threadfence();


            // Let followers prefetch.
            this->shfl_ptr_in_warp(0, prefetch_filepage_ids);
            this->shfl_ptr_in_warp(0, prefetch_cachepage_ids);

            this->pagecache_lock.release();

            __syncwarp();

            this->pages[ret]->lock.acquire();
            this->pages[ret]->read_in__no_lock(this->info1, this->info2, this->info3,
                    will_overwrite ? 1 : 0);
            this->pages[ret]->lock.release();

            cachepage_ids[0] = ret;
            size_t nr__ret = 1;
            for (int follower = 1; follower < 32; follower++) {
                if (prefetch_cachepage_ids[follower] != -1) {
                    cachepage_ids[follower] = prefetch_cachepage_ids[follower];
                    nr__ret++;
                } else
                    break;
            }

            return nr__ret;
        }

        // There is no page to be evicted now.
        // Waitting for a zero-reffed one.

        //printf("no page to be evicted, sleeping...\n");

        PageCacheImpl__info1 *leaders_waiting_for_evicting =
            this->__is_filepage_waiting_for_evicting(filepage_id);
        bool has_quota_to_wait = this->__has_quota_to_wait_for_evicting();

        if (leaders_waiting_for_evicting == nullptr && !has_quota_to_wait) {
            this->pagecache_lock.release();
            __nanosleep(1000);
            return this->__acquire_page_for_warp_leader(filepage_ids, cachepage_ids, nr_acquire_pages, will_overwrite);
        }

        if (leaders_waiting_for_evicting == nullptr && has_quota_to_wait) {
            leaders_waiting_for_evicting = new PageCacheImpl__info1();
            assert(leaders_waiting_for_evicting);
            leaders_waiting_for_evicting->filepage_id = filepage_id;
            leaders_waiting_for_evicting->nr_waiting = 0;
            this->__insert__filepage_waiting_for_evicting(filepage_id,
                    leaders_waiting_for_evicting);
        }
        leaders_waiting_for_evicting->nr_waiting++;
        __threadfence();
        this->pagecache_lock.release();

        // Let followers go.
        this->shfl_ptr_in_warp(0, (FilePageId *)nullptr);
        this->shfl_ptr_in_warp(0, (CachePageId *)nullptr);

        // Sleep-------------------------------------------------------------------
        leaders_waiting_for_evicting->wait_for_evicting.acquire();
        // Be awaken because the filepage is assigned-----------------------------

        this->pagecache_lock.acquire();
        ret = this->__get__cachepage_id(filepage_id);
        assert(ret != -1);

        //printf("I want filepage[%llx], MISS, but being assigned cachepage[%llx]!\n", filepage_id, ret);

        auto cur_waiting = leaders_waiting_for_evicting->nr_waiting;
        if (cur_waiting == 1) {
            delete leaders_waiting_for_evicting;
        } else {
            leaders_waiting_for_evicting->nr_waiting--;
        }

        __threadfence();
        this->pagecache_lock.release();
        this->pages[ret]->lock.acquire();
        this->pages[ret]->read_in__no_lock(this->info1, this->info2, this->info3,
                will_overwrite ? 1 : 0);
        this->pages[ret]->lock.release();
        cachepage_ids[0] = ret;
        return 1;
    }

    __forceinline__ __device__ void
    __release_page_for_warp_leader(FilePageId filepage_id) {
        //printf("I want to release the page %llx\n", filepage_id);
        this->pagecache_lock.acquire();
        CachePageId cachepage_id = this->__get__cachepage_id(filepage_id);
        if ((--(this->pages_ref[cachepage_id])) == 0) {
            // The last one reffing the cachepage exits.

            PageCacheImpl__info1 *p = this->__pop__filepage_waiting_for_evicting();
            if (p) {
                // There is someone waiting for evicting
                this->pages[cachepage_id]->assigned_to = p->filepage_id;
                this->pages_ref[cachepage_id] += p->nr_waiting;
                this->__erase__filepage__mapping(filepage_id);
                this->__insert__filepage__mapping_to__cachepage(p->filepage_id, cachepage_id);

                auto nr_waiting = p->nr_waiting;

                __threadfence();
                this->pagecache_lock.release();

                this->pages[cachepage_id]->lock.acquire();
                this->pages[cachepage_id]->write_back__no_lock(this->info1, this->info2, this->info3);
                this->pages[cachepage_id]->lock.release();

                for (size_t i = 0; i < nr_waiting; i++)
                    p->wait_for_evicting.release();

                return;
            }

            // Nobody waits for evicting
            this->__insert__zero_reffed_filepage(filepage_id);
        }
        __threadfence();
        this->pagecache_lock.release();
    }
//----------------------------------------------------------
    __forceinline__ __device__ PageCacheImpl__info1 *
    __is_filepage_waiting_for_evicting(FilePageId filepage_id) {
        FilePageId inner_filepage_id = filepage_id - this->filepage_id_base;
        auto *n = static_cast<MyLinklistNodeD<PageCacheImpl__info1 *> *>(this->filepages__waiting_for_evicting[inner_filepage_id]);
        if (n)
            return n->v;
        else
            return nullptr;
    }

    __forceinline__ __device__ bool
    __has_quota_to_wait_for_evicting() {
        return this->nr_waiting < this->nr_page;
    }

    __forceinline__ __device__ void
    __insert__filepage_waiting_for_evicting(FilePageId filepage_id,
                                             PageCacheImpl__info1 *p) {
        FilePageId inner_filepage_id = filepage_id - this->filepage_id_base;
        auto *n = new MyLinklistNodeD<PageCacheImpl__info1 *>();
        assert(n);
        n->v = p;
        this->filepages__waiting_for_evicting__list.enqueue(n);
        this->nr_waiting++;

        this->filepages__waiting_for_evicting[inner_filepage_id] = n;
    }

    __forceinline__ __device__ PageCacheImpl__info1 *
    __pop__filepage_waiting_for_evicting() {
        // get and erase
        if (this->nr_waiting == 0)
            return nullptr;

        auto *n = static_cast<MyLinklistNodeD<PageCacheImpl__info1 *> *>(this->filepages__waiting_for_evicting__list.pop());
        auto ret = n->v;
        this->nr_waiting--;

        this->filepages__waiting_for_evicting[ret->filepage_id] = nullptr;

        return ret;
    }
//------------------------------------------------------------
    __forceinline__ __device__ void
    __insert__filepage__mapping_to__cachepage(FilePageId filepage_id,
                                              CachePageId cachepage_id) {
        //printf("change map! filepage[%llx]->cachepage[%llx]\n", filepage_id, cachepage_id);
        FilePageId inner_filepage_id = filepage_id - this->filepage_id_base;
        this->filepage__to__cachepage[inner_filepage_id] = cachepage_id;
    }

    __forceinline__ __device__ void
    __erase__filepage__mapping(FilePageId filepage_id) {
        FilePageId inner_filepage_id = filepage_id - this->filepage_id_base;
        this->filepage__to__cachepage[inner_filepage_id] = -1;
    }

    __forceinline__ __device__ CachePageId
    __get__cachepage_id(FilePageId filepage_id) {
        FilePageId inner_filepage_id = filepage_id - this->filepage_id_base;
        return this->filepage__to__cachepage[inner_filepage_id];
    }
//-----------------------------------------------------------
    __forceinline__ __device__ void
    __insert__zero_reffed_filepage(FilePageId filepage_id) {
        FilePageId inner_filepage_id = filepage_id - this->filepage_id_base;
        auto *n = new MyLinklistNodeD<FilePageId>();
        assert(n);
        n->v = inner_filepage_id;
        this->zero_reffed_filepages__list.enqueue(n);

        this->zero_reffed_filepages[inner_filepage_id] = n;
        this->nr_zero_pages++;
    }

    __forceinline__ __device__ void
    __erase__zero_reffed_filepage(FilePageId filepage_id) {
        //printf("erase filepage_id[%llx]\n", filepage_id);
        FilePageId inner_filepage_id = filepage_id - this->filepage_id_base;
        auto *n = static_cast<MyLinklistNodeD<FilePageId> *>(this->zero_reffed_filepages[inner_filepage_id]);
        this->zero_reffed_filepages[inner_filepage_id] = nullptr;
        this->zero_reffed_filepages__list.detach_node(n);
        delete n;
        this->nr_zero_pages--;
    }

    __forceinline__ __device__ FilePageId
    __pop__zero_reffed_filepage_id() {
        // get and erase
        if (this->nr_zero_pages == 0)
            return -1;

        auto *n = static_cast<MyLinklistNodeD<FilePageId> *>(this->zero_reffed_filepages__list.pop());
        auto inner_filepage_id = n->v;
        delete n;

        this->zero_reffed_filepages[inner_filepage_id] = nullptr;
        this->nr_zero_pages--;

        return inner_filepage_id + this->filepage_id_base;
    }
//-----------------------------------------------------------

    FilePageId filepage_id_base, filepage_id_exclusive_end;
    int sync_parallelism;
    void *info1, *info2, *info3;

    cuda::binary_semaphore<cuda::thread_scope_device> pagecache_lock;

    void *nvme_controller;

    int page_size;

    uint64_t nr_page;
    uint64_t nr_file_page;

    CachePage **pages;
    uint64_t *pages_ref;

    size_t nr_waiting;
    MyLinklistNode **filepages__waiting_for_evicting;
    MyLinklist filepages__waiting_for_evicting__list;

    CachePageId *filepage__to__cachepage;

    MyLinklistNode **zero_reffed_filepages;
    MyLinklist zero_reffed_filepages__list;
    size_t nr_zero_pages;
};

using FilePageCacheLable = size_t;
class Batching_PageCache: public PageCache {
public:
    __device__
    Batching_PageCache(
            int page_size,
            PageCache **pagecaches,
            int pagecache_batching_size,
            int nr_pages__per_pagecache,
            PageCache **file_pagecache_lable__to__pagecache) {
        this->page_size = page_size;
        this->pagecaches = pagecaches;
        this->pagecache_batching_size = pagecache_batching_size;
        assert(__popc(nr_pages__per_pagecache) == 1); // which is power of 2
        this->bit_num_pages__per_pagecache = __popc(nr_pages__per_pagecache - 1);
        this->file_pagecache_lable__to__pagecache = file_pagecache_lable__to__pagecache;
    }

    __device__ virtual
    ~Batching_PageCache() {
        assert(0);
    }

    __device__ size_t
    acquire_pages__for_warp(
            const FilePageId *filepage_ids,
            CachePageId *cachepage_ids,
            size_t nr_acquire_pages,
            int will_overwrite) override {
        FilePageCacheLable l = filepage_ids[0] >> this->bit_num_pages__per_pagecache;
        size_t i;
        for (i = 0; i < nr_acquire_pages; i++) {
            FilePageCacheLable l1 = filepage_ids[i] >> this->bit_num_pages__per_pagecache;
            if (l != l1)
                break;
        }
        //printf("first filepage id[%llx] batching %d\n", filepage_ids[0], i);
        PageCache *pagecache = this->file_pagecache_lable__to__pagecache[l];
        return pagecache->acquire_pages__for_warp(filepage_ids, cachepage_ids, i, will_overwrite);
    }

    __device__ void
    set_page_dirty__for_warp(
            FilePageId filepage_id,
            CachePageId cachepage_id) override {
        FilePageCacheLable l = filepage_id >> this->bit_num_pages__per_pagecache;
        PageCache *pagecache = this->file_pagecache_lable__to__pagecache[l];
        pagecache->set_page_dirty__for_warp(filepage_id, cachepage_id);
    }

    __device__ void
    release_page__for_warp(
            FilePageId filepage_id) override {
        FilePageCacheLable l = filepage_id >> this->bit_num_pages__per_pagecache;
        PageCache *pagecache = this->file_pagecache_lable__to__pagecache[l];
        pagecache->release_page__for_warp(filepage_id);
    }

    __device__ void
    sync() override {
        for (int i = 0; i < this->pagecache_batching_size; i++)
            pagecaches[i]->sync();
    }

    __forceinline__ __device__ uint8_t *
    get_raw_page_buf(
            FilePageId filepage_id,
            CachePageId cachepage_id) override {
        FilePageCacheLable l = filepage_id >> this->bit_num_pages__per_pagecache;
        PageCache *pagecache = this->file_pagecache_lable__to__pagecache[l];
        return pagecache->get_raw_page_buf(filepage_id, cachepage_id);
    }

    __forceinline__ __device__ int
    get_page_bit_num() override {
        return __popc(this->page_size - 1);
    }

    __device__ void
    __set_filepage_id_base(FilePageId) { }

private:
    int page_size;
    PageCache **pagecaches;
    int pagecache_batching_size;
    int bit_num_pages__per_pagecache;
    PageCache **file_pagecache_lable__to__pagecache;
};

__host__ PageCache *
__internal__get_pagecache(
        uint64_t pagecache_capacity,
        int page_size,
        uint64_t size_of_virtual_space,
        CachePage *pages[],
        int sync_parallelism,
        void *info1, void *info2, void *info3) {
    uint64_t nr_page = pagecache_capacity / page_size;

    PageCache *pagecache;
    gpuErrchk(cudaMalloc(&pagecache, sizeof(PageCacheImpl)));

    uint64_t nr_file_page = size_of_virtual_space / page_size;
    MyLinklistNode **map1;
    CachePageId *map2;
    MyLinklistNode **map3;

    gpuErrchk(cudaMalloc(&map1, nr_file_page * sizeof(MyLinklistNode *)));
    gpuErrchk(cudaMalloc(&map2, nr_file_page * sizeof(CachePageId)));
    gpuErrchk(cudaMalloc(&map3, nr_file_page * sizeof(MyLinklistNode *)));

    RUN_ON_DEVICE({
        new (pagecache) PageCacheImpl (pagecache_capacity,
                page_size,
                size_of_virtual_space,
                pages,
                sync_parallelism,
                info1, info2, info3,
                map1, map2, map3);
    });
    return pagecache;
}

__host__ PageCache *
__internal__get_batched_pagecache(
        int page_size,
        PageCache **pagecaches,
        int pagecache_batching_size,
        int nr_pages__per_pagecache,
        size_t virtual_space_size) {
    PageCache *batching_pagecache;
    gpuErrchk(cudaMalloc(&batching_pagecache, sizeof(Batching_PageCache)));

    assert(virtual_space_size % page_size == 0);
    FilePageId nr_filepages = virtual_space_size / page_size;


    assert(one_nr__of__binary_int(nr_pages__per_pagecache) == 1); // which is power of 2
    int bit_num_pages__per_pagecache = one_nr__of__binary_int(nr_pages__per_pagecache - 1);


    assert(nr_filepages % nr_pages__per_pagecache == 0);
    FilePageCacheLable nr_file_pagecache_lables = nr_filepages / nr_pages__per_pagecache;

    PageCache **file_pagecache_lable__to__pagecache;
    gpuErrchk(cudaMalloc(&file_pagecache_lable__to__pagecache,
                nr_file_pagecache_lables * sizeof(PageCache *)));

    size_t nr_lables__per_pagecache = nr_file_pagecache_lables / pagecache_batching_size;
    //printf("nr_pages__per_pagecache[%llx] bit_nr[%d]\n",
    //    (size_t)nr_pages__per_pagecache, bit_num_pages__per_pagecache);
    //printf("nr_file_pagecache_lables[%llx]\n", nr_file_pagecache_lables);
    //printf("nr_lables__per_pagecache[%llx]\n", nr_lables__per_pagecache);
    //printf("pagecache_batching_size[%llx]\n", (size_t)pagecache_batching_size);
    RUN_ON_DEVICE({
        for (size_t idx_pagecache = 0;
                idx_pagecache < pagecache_batching_size;
                idx_pagecache++) {
	    pagecaches[idx_pagecache]->__set_filepage_id_base(
	        (idx_pagecache * nr_lables__per_pagecache) << bit_num_pages__per_pagecache);
            for (size_t i = 0; i < nr_lables__per_pagecache; i++)
                file_pagecache_lable__to__pagecache[idx_pagecache * nr_lables__per_pagecache + i] = pagecaches[idx_pagecache];
	}

        new (batching_pagecache) Batching_PageCache (
                page_size,
                pagecaches,
                pagecache_batching_size,
                nr_pages__per_pagecache,
                file_pagecache_lable__to__pagecache);
    });
    return batching_pagecache;
}


dev_fd_t
host_open_geminifs_file_for_device_without_backing_file(
        int page_size,
        uint64_t pagecache_capacity,
        int pagecache_batching_size) {
    size_t virtual_space_size = pagecache_capacity;
    size_t nr_pages = pagecache_capacity / page_size;
    assert(nr_pages % pagecache_batching_size == 0);
    size_t nr_pages__per_pagecache = nr_pages / pagecache_batching_size;

    assert(virtual_space_size % pagecache_batching_size == 0);
    size_t virtual_space_size__per_pagecache =
        virtual_space_size / pagecache_batching_size;

    PageCache **pagecaches;
    gpuErrchk(cudaMalloc(&pagecaches, sizeof(PageCache *) * pagecache_batching_size));

    for (int idx_pagecache = 0;
            idx_pagecache < pagecache_batching_size;
            idx_pagecache++) {
        uint8_t *all_raw_pages;
        CachePage_WithoutBacking *cachepage_structures;
        CachePage **pages;

        gpuErrchk(cudaMalloc(&all_raw_pages, nr_pages__per_pagecache * page_size));
        gpuErrchk(cudaMalloc(&cachepage_structures, nr_pages__per_pagecache * sizeof(CachePage_WithoutBacking)));
        gpuErrchk(cudaMalloc(&pages, nr_pages__per_pagecache * sizeof(CachePage *)));
        RUN_ON_DEVICE({
            for (size_t i = 0; i < nr_pages__per_pagecache; i++) {
                auto *cachepage = cachepage_structures + i;
                pages[i] = new (cachepage) CachePage_WithoutBacking(page_size, all_raw_pages + i * page_size);
            }
        });
        PageCache *pagecache = __internal__get_pagecache(
                nr_pages__per_pagecache * page_size,
                page_size,
                virtual_space_size__per_pagecache,
                pages,
                1,
                nullptr, nullptr, nullptr);
        RUN_ON_DEVICE({
            pagecaches[idx_pagecache] = pagecache;
        });
    }

    return __internal__get_batched_pagecache(
            page_size,
            pagecaches,
            pagecache_batching_size,
            nr_pages__per_pagecache,
            virtual_space_size);
}

__global__ void
device_xfer_geminifs_file(dev_fd_t fd,
                          vaddr_t va,
                          void *buf_dev_1,
                          size_t nbyte,
                          int is_read,
                          int nr_acquire_pages) {
    size_t nr_block = gridDim.x;
    size_t block_id = blockIdx.x;
    size_t nr_thread_per_block = blockDim.x;
    size_t nr_warp__per_block = nr_thread_per_block / 32;
    size_t warp_id__in_block = threadIdx.x / 32;
    //int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int lane = my_lane_id();

    assert(0 < nr_warp__per_block); // Every warp must hold 32 threads

    assert(32 == blockDim.x); // one warp per block

    if (nr_warp__per_block <= warp_id__in_block)
        // drop less-32-thread warp
        return;

    __syncwarp();
    size_t nr_thread_in_the_warp = __popc(__activemask());
    assert(nr_thread_in_the_warp == 32);

    uint8_t *buf_dev = (uint8_t *)buf_dev_1;

    PageCache *pagecache = (PageCache *)fd;
    int page_bit_num = pagecache->get_page_bit_num();

#define PAGE_SIZE(pg_bit) (1 << (pg_bit))
#define PAGE_ID(vaddr, pg_bit) ((vaddr) >> (pg_bit))
#define PAGE_BASE(vaddr, pg_bit) ((vaddr) & ~(PAGE_SIZE(pg_bit) - 1))
#define PAGE_BASE__BY_ID(pg_id, pg_bit) ((pg_id) << (pg_bit))
#define PAGE_OFST(vaddr, pg_bit) ((vaddr) & (PAGE_SIZE(pg_bit) - 1))

    __shared__ FilePageId begin, exclusive_end, inclusive_end;
    if (lane == 0) {
        begin = PAGE_ID(va, page_bit_num);
        exclusive_end = PAGE_ID(va + nbyte, page_bit_num);
        inclusive_end = exclusive_end - 1;
    }
    __syncwarp();

    //printf("va[0x%llx] nr_bytes[0x%llx]\n", va, nbyte);
    //printf("begin[0x%llx] exclusive_end[0x%llx] inclusive_end[0x%llx]\n", begin, exclusive_end, inclusive_end);


    if (begin == exclusive_end) {
        // not across the boundary of pages and in one page copy
	__shared__ CachePageId cachepage_id;
	pagecache->acquire_pages__for_warp(&begin, &cachepage_id, 1, 0);
        if (lane == 0) {
            uint8_t *cachepage_base = pagecache->get_raw_page_buf(begin, cachepage_id);
            if (is_read)
                memcpy(buf_dev, cachepage_base + PAGE_OFST(va, page_bit_num), nbyte);
            else
                memcpy(cachepage_base + PAGE_OFST(va, page_bit_num), buf_dev, nbyte);
        }
	__syncwarp();
	if (!is_read)
            pagecache->set_page_dirty__for_warp(begin, cachepage_id);
        pagecache->release_page__for_warp(begin);
        return;
    } else {
        // across the boundary of pages, and we deal non-full pages
        if (PAGE_OFST(va, page_bit_num) != 0) {
            // the first non-full page
            size_t n = PAGE_BASE__BY_ID(PAGE_ID(va, page_bit_num) + 1, page_bit_num) - va;
            __shared__ CachePageId cachepage_id;
            pagecache->acquire_pages__for_warp(&begin, &cachepage_id, 1, 0);
            if (lane == 0) {
                uint8_t *cachepage_base = pagecache->get_raw_page_buf(begin, cachepage_id);
                if (is_read)
                    memcpy(buf_dev, cachepage_base + PAGE_OFST(va, page_bit_num), n);
                else
                    memcpy(cachepage_base + PAGE_OFST(va, page_bit_num), buf_dev, n);
            }
	    __syncwarp();
	    if (!is_read)
                pagecache->set_page_dirty__for_warp(begin, cachepage_id);
            pagecache->release_page__for_warp(begin);
            va += n;
            buf_dev += n;
            nbyte -= n;
        }

        if (PAGE_OFST(va + nbyte, page_bit_num) != 0) {
            // the last non-full page
            size_t n = (va + nbyte) - PAGE_BASE(va + nbyte, page_bit_num);
            __shared__ CachePageId cachepage_id;
            pagecache->acquire_pages__for_warp(&inclusive_end, &cachepage_id, 1, 0);
            if (lane == 0) {
		//printf("the last non-full page last byte 0x[%llx]\n", n);
                uint8_t *cachepage_base = pagecache->get_raw_page_buf(inclusive_end, cachepage_id);
                uint8_t *dist_start = buf_dev + (nbyte - n);
                if (is_read)
                    memcpy(dist_start, cachepage_base, n);
                else
                    memcpy(cachepage_base, dist_start, n);
            }
	    __syncwarp();
	    if (!is_read)
                pagecache->set_page_dirty__for_warp(inclusive_end, cachepage_id);
            pagecache->release_page__for_warp(inclusive_end);
            nbyte -= n;
        }

    }

    assert(PAGE_OFST(va, page_bit_num) == 0);
    assert(PAGE_OFST(va + nbyte, page_bit_num) == 0);
    //printf("va[0x%llx] nr_bytes[0x%llx]\n", va, nbyte);

    if (lane == 0) {
        begin = PAGE_ID(va, page_bit_num);
        exclusive_end = PAGE_ID(va + nbyte, page_bit_num);
        inclusive_end = exclusive_end - 1;
    }
    __syncwarp();

    size_t nr_page = exclusive_end - begin;
    size_t nr_page__per_block = nr_page / nr_block;
    if (nr_page % nr_block != 0)
        nr_page__per_block++;

    FilePageId begin__block = begin + block_id * nr_page__per_block;
    FilePageId exclusive_end__block = begin__block + nr_page__per_block;
    if (exclusive_end <= begin__block)
        return;

    if (exclusive_end < exclusive_end__block)
        exclusive_end__block = exclusive_end;

    size_t nr_page__block = exclusive_end__block - begin__block;
    size_t nr_page__per_warp = nr_page__block / nr_warp__per_block;
    if (nr_page__block % nr_warp__per_block != 0)
        nr_page__per_warp++;

    FilePageId begin__warp = begin__block + warp_id__in_block * nr_page__per_warp;
    FilePageId exclusive_end__warp = begin__warp + nr_page__per_warp;
    if (exclusive_end__block <= begin__warp)
        return;

    if (exclusive_end__block < exclusive_end__warp)
        exclusive_end__warp = exclusive_end__block;

    uint32_t participating_mask = __activemask();
    participating_mask = __match_any_sync(participating_mask, begin__warp);
    int page_size = PAGE_SIZE(page_bit_num);


    //size_t warp_id__overview = warp_id__in_block + nr_warp__per_block * block_id;
    //if (0 == my_lane_id()) {
    //        printf("I'm warp %llx (in-block id %llx) threadIdx.x %llx, I account for [%llx, %llx). participating_mask[%llx]\n",
    //    		    warp_id__overview, warp_id__in_block, threadIdx.x, begin__warp, exclusive_end__warp, (uint64_t)participating_mask);
    //}

    __shared__ FilePageId filepage_ids[32];
    __shared__ CachePageId cachepage_ids[32];

    buf_dev = buf_dev + PAGE_BASE__BY_ID(begin__warp - begin, page_bit_num);
    for (FilePageId filepage_id = begin__warp;
            filepage_id < exclusive_end__warp;
            ) {
        size_t i;
        for (i = 0;
                i < nr_acquire_pages && filepage_id + i < exclusive_end__warp;
                i++) {
            filepage_ids[i] = filepage_id + i;
        }
        int nr_have_been_acquires = pagecache->acquire_pages__for_warp(
                filepage_ids,
                cachepage_ids,
                i,
                is_read ? 0 : 1);
        filepage_id += nr_have_been_acquires;

        for (i = 0; i < nr_have_been_acquires; i++) {
            FilePageId cur_filepage_id = filepage_ids[i];
            CachePageId cachepage_id = cachepage_ids[i];
            uint8_t *cachepage_base = pagecache->get_raw_page_buf(cur_filepage_id, cachepage_id);
            __syncwarp();
            if (is_read) {
                uint8_t *raw_page = cachepage_base;
                uint8_t *buf_dev_1 = buf_dev;
                for (size_t i = 0; i < page_size / 4096; i++) {
                    warp_memcpy_4kB(buf_dev_1, raw_page, participating_mask);
                    buf_dev_1 += 4096;
                    raw_page += 4096;
                }
            } else {
                uint8_t *raw_page = cachepage_base;
                uint8_t *buf_dev_1 = buf_dev;
                for (size_t i = 0; i < page_size / 4096; i++) {
                    warp_memcpy_4kB(raw_page, buf_dev_1, participating_mask);
                    buf_dev_1 += 4096;
                    raw_page += 4096;
                }
                pagecache->set_page_dirty__for_warp(cur_filepage_id, cachepage_id);
            }
            pagecache->release_page__for_warp(cur_filepage_id);
            buf_dev += PAGE_SIZE(page_bit_num);
        }

    }
}

__global__ void
device_sync(dev_fd_t dev_fd) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    PageCache *pagecache = (PageCache *)dev_fd;
    if (tid != 0)
        return;
    pagecache->sync();
}
