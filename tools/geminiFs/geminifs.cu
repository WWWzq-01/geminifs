//#include <stdio.h>
//#include <assert.h>
//#include <sys/types.h>
//#include <unistd.h>

#include <cuda/atomic>
#include <cuda/semaphore>
#include <cuco/static_map.cuh>
#include <cuco/static_set.cuh>

#include <cooperative_groups.h>

#include "geminifs.h"

#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

#define cdpErrchk(ans) { cdpAssert((ans), __FILE__, __LINE__); }
__device__ void cdpAssert(cudaError_t code, const char *file, int line, bool abort=true) {
   if (code != cudaSuccess) {
      printf("GPU kernel assert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) assert(0);
   }
}

__forceinline__ __device__ uint32_t
get_smid() {
     uint32_t ret;
     asm  ("mov.u32 %0, %smid;" : "=r"(ret) );
     return ret;
}

__forceinline__ __device__ int
lane_id() {
    int lane_id = threadIdx.x & 0x1f;
    return lane_id;
}

#include <cooperative_groups/memcpy_async.h>
__forceinline__ __device__
void warp_memcpy_4kB(void *dest_, const void *src_, uint32_t participating_mask) {
    uint32_t *dest = (uint32_t *)dest_;
    const uint32_t *src = (const uint32_t *)src_;
    int nr_participant = __popc(participating_mask);
    int lane = lane_id();
    int participant_id = __popc(participating_mask >> (32 - lane));
    //participant_id = 31 - participant_id;
    printf("participant_id is %u\n",participant_id);
    __threadfence();
    dest[participant_id * 32] = 1;
    __syncwarp(participating_mask);
    __syncthreads();
    __threadfence();
    if (participant_id == 2) {
        printf("after memcpy 4k\n");
        for (size_t i = 0; i < 256; i++)
            printf("%llx ", dest[i]);
        printf("\n");
    }
    return; 

    return;
    printf("One 4k!! lane %llx participant_id %llx nr_participant %llx participating_mask %llx\n",
            (uint64_t)lane, (uint64_t)participant_id, (uint64_t)nr_participant, (uint64_t)participating_mask);
    if (participant_id == 0) {
        for (size_t i = 0; i < 256; i++)
            printf("%llx ", src[i]);
        printf("\n");
    }
    __syncwarp(participating_mask);
    __syncthreads();
    __syncthreads();


    printf("participant_id = %llx src[participant_id] %llx\n", (uint64_t)participant_id, src[participant_id]);
    __syncwarp();
    __syncthreads();
    dest[participant_id] = src[participant_id];
    __threadfence();
    __syncthreads();
    __syncwarp();
    printf("dest[participant_id] %llx\n", dest[participant_id]);
    __syncwarp();
    if (participant_id == 0) {
        printf("after memcpy 4k\n");
        for (size_t i = 0; i < 256; i++)
            printf("%llx ", dest[i]);
        printf("\n");
    }
    return;
    __syncwarp(participating_mask);
    for (size_t i = participant_id;
            i < 32 / nr_participant;
            i += 16 * nr_participant) {
        printf("masknow = %llx \n", __activemask());
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
    __threadfence();
    }

    __syncwarp(participating_mask);
    if (participant_id == 0) {
        printf("after memcpy 4k\n");
        for (size_t i = 0; i < 256; i++)
            printf("%llx ", dest[i]);
        printf("\n");
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

using CachePageId = size_t;
using FilePageId = size_t;

enum CachePage_State {
    CACHEPAGE_INVALID,
    CACHEPAGE_CLEAN,
    CACHEPAGE_DIRTY,
};
class CachePage {
public:
    __forceinline__ __device__ void
    write_back__no_lock(void *nvme_controller) {
        if (this->state == CACHEPAGE_DIRTY) {
            this->nvme_write(nvme_controller, this->get_nvmeofst(this->content_of));
            this->state = CACHEPAGE_CLEAN;
            __threadfence();
        }
    }
    __forceinline__ __device__ void
    read_in__no_lock(void *nvme_controller) {
        if ((this->content_of != this->assigned_to) || this->state == CACHEPAGE_INVALID) {
            this->write_back__no_lock(nvme_controller);

            // Here, the state is INVALID or CLEAN

            this->nvme_read(nvme_controller, this->get_nvmeofst(this->assigned_to));
            this->content_of = this->assigned_to;
            this->state = CACHEPAGE_CLEAN;
            __threadfence();
        }
    }

    virtual __device__ nvme_ofst_t get_nvmeofst(FilePageId filepage_id) = 0;
    virtual __device__ void nvme_write(void *nvme_controller, nvme_ofst_t nvme_ofst) = 0;
    virtual __device__ void nvme_read(void *nvme_controller, nvme_ofst_t nvme_ofst) = 0;

    __forceinline__ __device__ void
    sync(void *nvme_controller) {
        this->lock.acquire();
        this->write_back__no_lock(nvme_controller);
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
    void *buf;
    enum CachePage_State state;
    cuda::binary_semaphore<cuda::thread_scope_device> lock;
};

class CachePage_Allocated: public CachePage {
public:
    __device__
    CachePage_Allocated(void *buf_) {
        this->buf = buf_;
    }
    __device__ nvme_ofst_t get_nvmeofst(FilePageId filepage_id) {return -1;}
    __device__ void nvme_write(void *nvme_controller, nvme_ofst_t nvme_ofst) { }
    __device__ void nvme_read(void *nvme_controller, nvme_ofst_t nvme_ofst) {assert(0);}
};

class PageCache {
public:
    virtual __device__ CachePageId
    acquire_page(FilePageId filepage_id) = 0;

    virtual __device__ void
    set_page_dirty(CachePageId cachepage_id) = 0;

    virtual __device__ void
    release_page(FilePageId filepage_id) = 0;

    virtual __device__ uint8_t *
    get_raw_page_buf(CachePageId cachepage_id) = 0;

    virtual __device__ int
    get_page_bit_num() = 0;
};

class PageCacheImpl__info1 {
public:
    FilePageId filepage_id;
    cuda::counting_semaphore<cuda::thread_scope_device> wait_for_evicting;
    int nr_waiting;
};

template <typename Map1_Ref, typename Map2_Ref, typename Map3_Ref>
class PageCacheImpl: public PageCache {
public:
    __device__ PageCacheImpl(uint64_t pagecache_capacity,
                             int page_size,
                             bool no_backing_file,
                             uint64_t size_of_virtual_space,
                             Map1_Ref map1_ref,
                             Map2_Ref map2_ref,
                             Map3_Ref map3_ref,
                             void *used_for_pages,
                             void *used_for_pages_ref,
                             void *used_for_cachepage_structure,
                             void *used_for_raw_page_space):
        filepages__waiting_for_evicting__ref(map1_ref),
        nr_waiting(0),
        filepage__to__cachepage__ref(map2_ref),
        zero_reffed_filepages__ref(map3_ref) {
            if (no_backing_file)
                assert(size_of_virtual_space == pagecache_capacity);

            this->pagecache_lock.release();

            uint64_t nr_page = pagecache_capacity / page_size;

            this->page_size = page_size;
            this->nr_page = nr_page;

            this->pages = (CachePage **)used_for_pages;
            this->pages_ref = (uint64_t *)used_for_pages_ref;


            if (no_backing_file) {
                auto *cachepage_structures = (CachePage_Allocated *)used_for_cachepage_structure;
                uint8_t *raw_cachepages = (uint8_t *)used_for_raw_page_space;
                for (CachePageId cachepage_id = 0; cachepage_id < nr_page; cachepage_id++) {
                    FilePageId filepage_id = cachepage_id;
                    auto *page = new (cachepage_structures + cachepage_id) CachePage_Allocated(raw_cachepages + cachepage_id * page_size);
                    page->cachepage_id = cachepage_id;
                    page->content_of = filepage_id;
                    page->assigned_to = filepage_id;
                    page->state = CACHEPAGE_CLEAN;
                    page->lock.release();

                    this->pages[cachepage_id] = page;
                    this->pages_ref[cachepage_id] = 1; // the Ref Count is at lease 1, thus the page won't be evicted.
                    this->__insert__filepage__mapping_to__cachepage(filepage_id, cachepage_id);
                    printf("%llx\n", cachepage_id);
                }
                
            } else {
                for (CachePageId cachepage_id = 0; cachepage_id < nr_page; cachepage_id++) {
                    assert(0);
                    //FilePageId filepage_id = cachepage_id;
                    //auto *page = new CachePage_Allocated(page_size);
                    //assert(page);

                    //page->cachepage_id = cachepage_id;
                    //page->content_of = filepage_id;
                    //page->assigned_to = filepage_id;
                    //page->state = CACHEPAGE_INVALID;

                    //this->pages[cachepage_id] = page;
                    //this->pages_ref[cachepage_id] = 0;

                    //this->__insert__filepage__mapping_to__cachepage(filepage_id, cachepage_id);
                    //this->__insert__zero_reffed_filepage(filepage_id);
                }
            }
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

    __device__ CachePageId
    acquire_page(FilePageId filepage_id) {
        CachePageId cachepage_id;

        uint32_t mask = __activemask();
        mask = __match_any_sync(mask, (uint64_t)this);
        mask = __match_any_sync(mask, filepage_id);
        uint32_t warp_leader = __ffs(mask) - 1;
        int lane = lane_id();
        if (lane == warp_leader) {
            printf("acquire_page %llx\n", filepage_id);
            cachepage_id = this->__acquire_page_for_warp_leader(filepage_id);
        }
        cachepage_id = __shfl_sync(mask, cachepage_id, warp_leader);
        return cachepage_id;
    }

    __device__ void
    set_page_dirty(CachePageId cachepage_id) {
        uint32_t mask = __activemask();
        mask = __match_any_sync(mask, (uint64_t)this);
        mask = __match_any_sync(mask, cachepage_id);
        uint32_t warp_leader = __ffs(mask) - 1;
        int lane = lane_id();
        if (lane == warp_leader)
            this->pages[cachepage_id]->set_dirty();
    }

    __device__ void
    release_page(FilePageId filepage_id) {
        uint32_t mask = __activemask();
        mask = __match_any_sync(mask, (uint64_t)this);
        mask = __match_any_sync(mask, filepage_id);
        uint32_t warp_leader = __ffs(mask) - 1;
        int lane = lane_id();
        if (lane == warp_leader)
            this->__release_page_for_warp_leader(filepage_id);
        __syncwarp(mask);
    }

    __forceinline__ __device__ uint8_t *
    get_raw_page_buf(CachePageId cachepage_id) {
        return (uint8_t *)this->pages[cachepage_id]->buf;
    }

    __forceinline__ __device__ int
    get_page_bit_num() {
        return __popc(this->page_size - 1);
    }
private:
    __forceinline__ __device__ CachePageId
    __acquire_page_for_warp_leader(FilePageId filepage_id) {
        CachePageId ret;

        this->pagecache_lock.acquire();

        printf("I'm in. I want %llx!!\n", filepage_id);
        ret = this->__get__cachepage_id(filepage_id);
        if (ret != -1) {
            // Page Hit!
        printf("Hit!!\n");
            size_t cur_ref = (++(this->pages_ref[ret]));
            if (cur_ref == 1)
                this->__erase__zero_reffed_filepage(filepage_id);

            __threadfence();
            this->pagecache_lock.release();

        printf("I release the lock\n");
            this->pages[ret]->lock.acquire();
            this->pages[ret]->read_in__no_lock(this->nvme_controller);
            this->pages[ret]->lock.release();

        printf("I leave~\n");
            return ret;
        }

        assert(0);
        printf("Miss!!\n");

        // Miss
        // ret == -1

        FilePageId evicted_filepage_id = this->__pop__zero_reffed_filepage_id();
        if (evicted_filepage_id != -1) {
            // Here we find a zero-reffed page to be evicted
            ret = this->__get__cachepage_id(evicted_filepage_id);
            ++(this->pages_ref[ret]);

            this->__erase__filepage__mapping(evicted_filepage_id);
            this->__insert__filepage__mapping_to__cachepage(filepage_id, ret);

            this->pages[ret]->assigned_to = filepage_id;

            __threadfence();
            this->pagecache_lock.release();

            this->pages[ret]->lock.acquire();
            this->pages[ret]->read_in__no_lock(this->nvme_controller);
            this->pages[ret]->lock.release();
            return ret;
        }

        // There is no page to be evicted now.
        // Waitting for a zero-reffed one.

        PageCacheImpl__info1 *leaders_waiting_for_evicting =
            this->__is_filepage_waiting_for_evicting(filepage_id);
        bool has_quota_to_wait = this->__has_quota_to_wait_for_evicting();

        if (leaders_waiting_for_evicting == nullptr && !has_quota_to_wait) {
            this->pagecache_lock.release();
            __nanosleep(200);
            return this->__acquire_page_for_warp_leader(filepage_id);
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

        // Sleep-------------------------------------------------------------------
        leaders_waiting_for_evicting->wait_for_evicting.acquire();
        // Be awaken because the filepage is assigned-----------------------------

        this->pagecache_lock.acquire();
        ret = this->__get__cachepage_id(filepage_id);
        assert(ret != -1);

        auto cur_waiting = leaders_waiting_for_evicting->nr_waiting;
        if (cur_waiting == 1) {
            delete leaders_waiting_for_evicting;
        } else {
            leaders_waiting_for_evicting->nr_waiting--;
        }

        __threadfence();
        this->pagecache_lock.release();
        this->pages[ret]->lock.acquire();
        this->pages[ret]->read_in__no_lock(this->nvme_controller);
        this->pages[ret]->lock.release();
        return ret;
    }

    __forceinline__ __device__ void
    __release_page_for_warp_leader(FilePageId filepage_id) {
        this->pagecache_lock.acquire();
        printf("I want to release the page %llx\n", filepage_id);
        CachePageId cachepage_id = this->__get__cachepage_id(filepage_id);
        if ((--(this->pages_ref[cachepage_id])) == 0) {
            // The last one reffing the cachepage exits.
            printf("I'm the last one!\n", filepage_id);

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
                this->pages[cachepage_id]->write_back__no_lock(this->nvme_controller);
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
        auto found = this->filepages__waiting_for_evicting__ref.find(filepage_id);
        if (found != this->filepages__waiting_for_evicting__ref.end()) {
            auto *n = static_cast<MyLinklistNodeD<PageCacheImpl__info1 *> *>(found->second);
            return n->v;
        } else
            return nullptr;
    }

    __forceinline__ __device__ bool
    __has_quota_to_wait_for_evicting() {
        return this->nr_waiting < this->filepages__waiting_for_evicting__ref.capacity() / 2;
    }

    __forceinline__ __device__ void
    __insert__filepage_waiting_for_evicting(FilePageId filepage_id,
                                             PageCacheImpl__info1 *p) {
        auto *n = new MyLinklistNodeD<PageCacheImpl__info1 *>();
        assert(n);
        n->v = p;
        this->filepages__waiting_for_evicting__list.enqueue(n);
        this->nr_waiting++;

        assert(this->filepages__waiting_for_evicting__ref.insert(cuco::pair{filepage_id, n}));
    }

    __forceinline__ __device__ PageCacheImpl__info1 *
    __pop__filepage_waiting_for_evicting() {
        // get and erase
        auto *n = static_cast<MyLinklistNodeD<PageCacheImpl__info1 *> *>(this->filepages__waiting_for_evicting__list.pop());
        auto ret = n->v;
        this->nr_waiting--;

        assert(this->filepages__waiting_for_evicting__ref.erase(ret->filepage_id));

        return ret;
    }
//------------------------------------------------------------
    __forceinline__ __device__ void
    __insert__filepage__mapping_to__cachepage(FilePageId filepage_id,
                                              CachePageId cachepage_id) {
        assert(this->filepage__to__cachepage__ref.insert(cuco::pair{filepage_id, cachepage_id}));
    }

    __forceinline__ __device__ void
    __erase__filepage__mapping(FilePageId filepage_id) {
        assert(this->filepage__to__cachepage__ref.erase(filepage_id));
    }

    __forceinline__ __device__ CachePageId
    __get__cachepage_id(FilePageId filepage_id) {
        auto found = this->filepage__to__cachepage__ref.find(filepage_id);
        if (found != this->filepage__to__cachepage__ref.end())
            return found->second;
        else
            return -1;
    }
//-----------------------------------------------------------
    __forceinline__ __device__ void
    __insert__zero_reffed_filepage(FilePageId filepage_id) {
        auto *n = new MyLinklistNodeD<FilePageId>();
        assert(n);
        n->v = filepage_id;
        this->zero_reffed_filepages__list.enqueue(n);

        assert(this->zero_reffed_filepages__ref.insert(cuco::pair{filepage_id, n}));
    }

    __forceinline__ __device__ void
    __erase__zero_reffed_filepage(FilePageId filepage_id) {
        MyLinklistNodeD<FilePageId> *n = nullptr;
        auto found = this->zero_reffed_filepages__ref.find(filepage_id);
        if (found != this->zero_reffed_filepages__ref.end())
            n = static_cast<MyLinklistNodeD<FilePageId> *>(found->second);

        assert(n);

        assert(this->zero_reffed_filepages__ref.erase(filepage_id));
        this->zero_reffed_filepages__list.detach_node(n);
        delete n;
    }

    __forceinline__ __device__ FilePageId
    __pop__zero_reffed_filepage_id() {
        // get and erase
        auto *n = static_cast<MyLinklistNodeD<FilePageId> *>(this->zero_reffed_filepages__list.pop());
        auto filepage_id = n->v;
        delete n;

        assert(this->zero_reffed_filepages__ref.erase(filepage_id));

        return filepage_id;
    }
//-----------------------------------------------------------

    cuda::binary_semaphore<cuda::thread_scope_device> pagecache_lock;

    void *nvme_controller;

    int page_size;

    uint64_t nr_page;

    CachePage **pages;
    uint64_t *pages_ref;

    size_t nr_waiting;
    Map1_Ref filepages__waiting_for_evicting__ref;
    MyLinklist filepages__waiting_for_evicting__list;

    Map2_Ref filepage__to__cachepage__ref;

    Map3_Ref zero_reffed_filepages__ref;
    MyLinklist zero_reffed_filepages__list;
};

template <typename Map1_Ref, typename Map2_Ref, typename Map3_Ref>
static __global__ void
host_open_geminifs_file_for_device_2(PageCache **pagecache_dev,
        uint64_t pagecache_capacity,
        int page_size,
        bool no_backing_file,
        uint64_t size_of_virtual_space,
        Map1_Ref map1_ref,
        Map2_Ref map2_ref,
        Map3_Ref map3_ref,
        void *used_for_pages,
        void *used_for_pages_ref,
        void *used_for_cachepage_structure,
        void *used_for_raw_page_space) {
    auto tid = threadIdx.x + blockIdx.x * blockDim.x;
    if (tid != 0)
        return;

    auto *pagecache = new PageCacheImpl<Map1_Ref, Map2_Ref, Map3_Ref>
        (pagecache_capacity,
         page_size,
         no_backing_file,
         size_of_virtual_space,
         map1_ref,
         map2_ref,
         map3_ref,
         used_for_pages,
         used_for_pages_ref,
         used_for_cachepage_structure,
         used_for_raw_page_space);
    assert(pagecache);
    *pagecache_dev = pagecache;
}

static PageCache *
host_open_geminifs_file_for_device_1(uint64_t pagecache_capacity,
        int page_size,
        bool no_backing_file,
        uint64_t size_of_virtual_space) {
    PageCache **pagecache_ptr_dev;
    gpuErrchk(cudaMalloc(&pagecache_ptr_dev, sizeof(&pagecache_ptr_dev)));

    uint64_t nr_page = pagecache_capacity / page_size;

    // Initial host part of containers
    FilePageId constexpr empty_FilePageId_sentinel = -1;
    CachePageId constexpr empty_CachePageId_sentinel = -1;
    MyLinklistNode constexpr *sentinel = nullptr;

    auto *filepages__waiting_for_evicting =
        new cuco::static_map
        <FilePageId,
        MyLinklistNode *,
        cuco::extent<std::size_t>,
        cuda::thread_scope_device,
        thrust::equal_to<FilePageId>,
        cuco::linear_probing<1, cuco::default_hash_function<FilePageId>>>
            (2 * nr_page,
             cuco::empty_key{empty_FilePageId_sentinel},
             cuco::empty_value{sentinel});
    auto map1_ref = filepages__waiting_for_evicting->ref(cuco::insert, cuco::find, cuco::erase);

    auto *filepage__to__cachepage =
        new cuco::static_map
        <FilePageId,
        CachePageId,
        cuco::extent<std::size_t>,
        cuda::thread_scope_device,
        thrust::equal_to<FilePageId>,
        cuco::linear_probing<1, cuco::default_hash_function<FilePageId>>>
            (2 * nr_page,
             cuco::empty_key{empty_FilePageId_sentinel},
             cuco::empty_value{empty_CachePageId_sentinel});
    auto map2_ref = filepage__to__cachepage->ref(cuco::insert, cuco::find, cuco::erase);

    auto *zero_reffed_filepages =
        new cuco::static_map
        <FilePageId,
        MyLinklistNode *,
        cuco::extent<std::size_t>,
        cuda::thread_scope_device,
        thrust::equal_to<FilePageId>,
        cuco::linear_probing<1, cuco::default_hash_function<FilePageId>>>
            (2 * nr_page,
             cuco::empty_key{empty_FilePageId_sentinel},
             cuco::empty_value{sentinel});
    auto map3_ref = zero_reffed_filepages->ref(cuco::insert, cuco::find, cuco::erase);

    void *used_for_pages;
    void *used_for_pages_ref;
    void *used_for_cachepage_structure;
    void *used_for_raw_page_space;
    gpuErrchk(cudaMalloc(&used_for_pages, sizeof(CachePage *) * nr_page));
    gpuErrchk(cudaMalloc(&used_for_pages_ref, sizeof(uint64_t) * nr_page));
    if (no_backing_file) {
        gpuErrchk(cudaMalloc(&used_for_cachepage_structure, sizeof(CachePage_Allocated) * nr_page));
        gpuErrchk(cudaMalloc(&used_for_raw_page_space, page_size * nr_page));
    } else
        assert(0);

    host_open_geminifs_file_for_device_2<<<1, 1>>>(pagecache_ptr_dev,
            pagecache_capacity,
            page_size,
            no_backing_file,
            size_of_virtual_space,
            map1_ref,
            map2_ref,
            map3_ref,
            used_for_pages,
            used_for_pages_ref,
            used_for_cachepage_structure,
            used_for_raw_page_space);

    cudaDeviceSynchronize();

    PageCache *pagecache_dev;
    gpuErrchk(cudaMemcpy(&pagecache_dev, pagecache_ptr_dev, sizeof(pagecache_dev),
                cudaMemcpyDeviceToHost));
    gpuErrchk(cudaFree(pagecache_ptr_dev));
    return pagecache_dev;
}

dev_fd_t
host_open_geminifs_file_for_device(host_fd_t host_fd, uint64_t pagecache_capacity) {
    struct geminiFS_hdr *hdr = host_fd;

    nvme_ofst_t *l1__dev;
    gpuErrchk(cudaMalloc(&l1__dev, hdr->first_block_base));

    struct geminiFS_hdr *hdr__file = (struct geminiFS_hdr *)malloc(hdr->first_block_base);

    assert((off_t)(-1) !=
            lseek(hdr->fd, 0, SEEK_SET)
          );
    assert(hdr->first_block_base ==
            read(hdr->fd, hdr__file, hdr->first_block_base)
          );
    gpuErrchk(cudaMemcpy(
                l1__dev,
                hdr__file->l1,
                hdr__file->first_block_base - sizeof(*hdr),
                cudaMemcpyHostToDevice));

    free(hdr__file);

    //dev_fd_t ret;
    //ret.l1__dev = l1__dev;
    //ret.block_bit = hdr->block_bit;
    //ret.nr_l1 = hdr->nr_l1;

    PageCache *pagecache_dev = host_open_geminifs_file_for_device_1(pagecache_capacity,
            1 << hdr->block_bit,
            false,
            hdr->virtual_space_size);
    return pagecache_dev;
}

dev_fd_t
host_open_geminifs_file_for_device_without_backing_file(int page_size, uint64_t pagecache_capacity) {
    PageCache *pagecache_dev = host_open_geminifs_file_for_device_1(pagecache_capacity,
            page_size,
            true,
            pagecache_capacity);
    return pagecache_dev;
}

__global__ void
device_xfer_geminifs_file(dev_fd_t fd,
                          vaddr_t va,
                          void *buf_dev_1,
                          size_t nbyte,
                          int is_read) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;

    uint8_t *buf_dev = (uint8_t *)buf_dev_1;

    PageCache *pagecache = (PageCache *)fd;
    int page_bit_num = pagecache->get_page_bit_num();

#define PAGE_SIZE(pg_bit) (1 << (pg_bit))
#define PAGE_ID(vaddr, pg_bit) ((vaddr) >> (pg_bit))
#define PAGE_BASE(vaddr, pg_bit) ((vaddr) & ~(PAGE_SIZE(pg_bit) - 1))
#define PAGE_BASE__BY_ID(pg_id, pg_bit) ((pg_id) << (pg_bit))
#define PAGE_OFST(vaddr, pg_bit) ((vaddr) & (PAGE_SIZE(pg_bit) - 1))

    FilePageId begin = PAGE_ID(va, page_bit_num);
    FilePageId exclusive_end = PAGE_ID(va + nbyte, page_bit_num);
    FilePageId inclusive_end = exclusive_end - 1;
    if (begin == inclusive_end) {
        // not across the boundary of pages and in one page copy
        if (tid == 0) {
            CachePageId cachepage_id = pagecache->acquire_page(begin);
            uint8_t *cachepage_base = pagecache->get_raw_page_buf(cachepage_id);
            if (is_read) {
                memcpy(buf_dev, cachepage_base + PAGE_OFST(va, page_bit_num), nbyte);
            } else {
                memcpy(cachepage_base + PAGE_OFST(va, page_bit_num), buf_dev, nbyte);
                pagecache->set_page_dirty(cachepage_id);
            }
            pagecache->release_page(begin);
        }
        return;
    } else {
        // across the boundary of pages, and we deal non-full pages
        if (PAGE_OFST(va, page_bit_num) != 0) {
            // the first non-full page
            size_t n = PAGE_BASE__BY_ID(PAGE_ID(va, page_bit_num) + 1, page_bit_num) - va;
            if (tid == 0) {
                CachePageId cachepage_id = pagecache->acquire_page(begin);
                uint8_t *cachepage_base = pagecache->get_raw_page_buf(cachepage_id);
                if (is_read) {
                    memcpy(buf_dev, cachepage_base + PAGE_OFST(va, page_bit_num), n);
                } else {
                    memcpy(cachepage_base + PAGE_OFST(va, page_bit_num), buf_dev, n);
                    pagecache->set_page_dirty(cachepage_id);
                }
                pagecache->release_page(begin);
            }
            va += n;
            buf_dev += n;
            nbyte -= n;
        }

        if (PAGE_OFST(va + nbyte, page_bit_num) != 0) {
            // the last non-full page
            size_t n = (va + nbyte) - PAGE_BASE(va + nbyte, page_bit_num);
            if (tid == 0) {
                CachePageId cachepage_id = pagecache->acquire_page(inclusive_end);
                uint8_t *cachepage_base = pagecache->get_raw_page_buf(cachepage_id);
                uint8_t *dist_start = buf_dev + (nbyte - n);
                if (is_read) {
                    memcpy(dist_start, cachepage_base, n);
                } else {
                    memcpy(cachepage_base, dist_start, n);
                    pagecache->set_page_dirty(cachepage_id);
                }
                pagecache->release_page(inclusive_end);
            }
            nbyte -= n;
        }

    }

    assert(PAGE_OFST(va, page_bit_num) == 0);
    assert(PAGE_OFST(va + nbyte, page_bit_num) == 0);

    begin = PAGE_ID(va, page_bit_num);
    exclusive_end = PAGE_ID(va + nbyte, page_bit_num);

    size_t nr_block = gridDim.x;
    size_t block_id = blockIdx.x;
    size_t nr_thread_per_block = blockDim.x;
    size_t nr_warp__per_block = nr_thread_per_block / 32;
    size_t warp_id__in_block = threadIdx.x / 32;

    if (nr_warp__per_block == 0)
        // only one warp holding less 32 threads
        nr_warp__per_block++;

    if (nr_warp__per_block <= warp_id__in_block)
        // drop less-32-thread warp
        return;

    size_t nr_thread_in_the_warp = __popc(__activemask());
    assert(__popc(nr_thread_in_the_warp) == 1); // is power of 2

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
    printf("participating_mask %llx\n",participating_mask);
    participating_mask = __match_any_sync(participating_mask, begin__warp);
    printf("participating_mask %llx\n",participating_mask);
    int page_size = PAGE_SIZE(page_bit_num);


    size_t warp_id__overview = warp_id__in_block + nr_warp__per_block * block_id;
    printf("I'm warp %llx (in-block id %llx) threadIdx.x %llx, I account for [%llx, %llx)\n",
            warp_id__overview, warp_id__in_block, threadIdx.x, begin__warp, exclusive_end__warp);

    buf_dev = buf_dev + PAGE_BASE__BY_ID(begin__warp - begin, page_bit_num);
    for (FilePageId filepage_id = begin__warp;
            filepage_id < exclusive_end__warp;
            filepage_id++) {
        CachePageId cachepage_id = pagecache->acquire_page(filepage_id);
        uint8_t *cachepage_base = pagecache->get_raw_page_buf(cachepage_id);
       // printf("I'm warp %llx, I get filepage %llx\n\n",
       //         warp_id__overview, filepage_id);
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
            pagecache->set_page_dirty(cachepage_id);
        }
        pagecache->release_page(filepage_id);
        buf_dev += PAGE_SIZE(page_bit_num);
    }
}

__global__ void
test_for_memcpy4k(int* buffer) {
    uint32_t participating_mask = __activemask();

    uint64_t *buf1 = (uint64_t *)malloc(4096);

    for (size_t i = 0; i < 256; i++)
        buf1[i] = i + 2;

    uint64_t *buf2 = (uint64_t *)malloc(4096);
    warp_memcpy_4kB(buf2, (void*)buffer, participating_mask);
}

int
main() {
  int block_size = 1ull << 12; /* 4096 */
  size_t capacity = 8 * (1ull << 10); /* 32k */


    gpuErrchk(cudaSetDevice(1));
    int* buffer;  
    int bufferSize = 4096 / 32;
    int* hostBuffer = (int*)malloc(bufferSize * sizeof(int));  
    cudaMalloc(&buffer, bufferSize * sizeof(int));  

    test_for_memcpy4k<<<1, 32>>>(buffer);
    cudaDeviceSynchronize();

    cudaMemcpy(hostBuffer, buffer, bufferSize * sizeof(int), cudaMemcpyDeviceToHost); 
    printf("buf:\n");
    for (int i = 0; i < 256; ++i) {  
        printf("buffer[%d] = %d\n", i, hostBuffer[i]);  
    }  
    printf("\n");
    test_for_memcpy4k<<<1, 32>>>(buffer);
    cudaDeviceSynchronize();
    cudaMemcpy(hostBuffer, buffer, bufferSize * sizeof(int), cudaMemcpyDeviceToHost); 
    for (int i = 0; i < 256; ++i) {  
        printf("buffer[%d] = %d\n", i, hostBuffer[i]);  
    }  
  return 0;


  size_t heapsz = 1 * (1ull << 30);
  gpuErrchk(cudaDeviceSetLimit(cudaLimitMallocHeapSize, heapsz));

  dev_fd_t dev_fd =
      host_open_geminifs_file_for_device_without_backing_file(block_size, capacity);


  size_t buf_size = 8 * (1ull << 10); /* 16k */

  uint64_t *whole_host_buf = (uint64_t *)malloc(capacity);
  uint64_t *another_whole_host_buf = (uint64_t *)malloc(capacity);

  uint64_t *dev_buf1;
  uint64_t *dev_buf2;
  gpuErrchk(cudaMalloc(&dev_buf1, buf_size));
  gpuErrchk(cudaMalloc(&dev_buf2, buf_size));

  for (size_t i = 0; i < capacity / sizeof(uint64_t); i++)
    whole_host_buf[i] = i + 2;

  for (vaddr_t va = 0; va < capacity; va += buf_size) {
      gpuErrchk(cudaMemcpy(dev_buf1, (uint8_t *)whole_host_buf + va, buf_size, cudaMemcpyHostToDevice));
      cudaDeviceSynchronize();
      device_xfer_geminifs_file<<<108, 32>>>(dev_fd, va, dev_buf1, buf_size, 0);
      cudaDeviceSynchronize();
      device_xfer_geminifs_file<<<108, 32>>>(dev_fd, va, dev_buf2, buf_size, 1);
      cudaDeviceSynchronize();
      gpuErrchk(cudaMemcpy((uint8_t *)another_whole_host_buf + va, dev_buf2, buf_size, cudaMemcpyDeviceToHost));
      cudaDeviceSynchronize();
  }

  for (size_t i = 0; i < capacity / sizeof(uint64_t); i++) {
      std::cout << whole_host_buf[i] << " ";
      //assert(another_whole_host_buf[i] == i + 2);
  }
  for (size_t i = 0; i < capacity / sizeof(uint64_t); i++) {
      std::cout << another_whole_host_buf[i] << " ";
      //assert(another_whole_host_buf[i] == i + 2);
  }

  return 0;
}


//__device__ static nvme_ofst_t
//device__convert_va__to(dev_fd_t dev_fd,
//                       vaddr_t va) {
//  auto nr_l1 = dev_fd.nr_l1;
//  auto block_bit = dev_fd.block_bit;
//
//  uint64_t l1_idx = va >> block_bit;
//
//  if (l1_idx < nr_l1)
//    return dev_fd.l1__dev[l1_idx];
//
//  return 0;
//}
//
//__global__ void
//device_convert_va(dev_fd_t dev_fd,
//                  vaddr_t va,
//                  nvme_ofst_t *ret__dev) {
//  *ret__dev = device__convert_va__to(dev_fd, va);
//}
//  
//nvme_ofst_t
//host_convert_va__using_device(dev_fd_t dev_fd,
//        vaddr_t va) {
//  nvme_ofst_t *ret__dev;
//  assert(cudaSuccess ==
//    cudaMalloc(&ret__dev, sizeof(nvme_ofst_t))
//  );
//
//  device_convert_va<<<1, 1>>>(dev_fd, va, ret__dev);
//
//  nvme_ofst_t ret;
//  assert(cudaSuccess ==
//    cudaMemcpy(
//      &ret,
//      ret__dev,
//      sizeof(nvme_ofst_t),
//      cudaMemcpyDeviceToHost)
//  );
//
//  assert(cudaSuccess == cudaFree(ret__dev));
//  return ret;
//}
