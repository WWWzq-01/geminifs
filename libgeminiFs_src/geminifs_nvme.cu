#include "geminifs_api.cuh"
#include "geminifs_internal.cuh"

#include <ctrl.h>
#include <buffer.h>
#include <queue.h>
#include <nvm_parallel_queue.h>
#include <nvm_types.h>
#include <nvm_util.h>
#include <nvm_cmd.h>
#include "get-offset/get-offset.h"

#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }

class QueueAcquireHelper {
public:
    __device__
    QueueAcquireHelper(int nr_queues) {
        this->lock.release();
        this->queue_now = 0;
        this->cmd_count = new int[nr_queues];
        for (size_t i = 0; i < nr_queues; i++)
            this->cmd_count[i] = 4096;

        this->nr_queues = nr_queues;
        this->locks = new cuda::binary_semaphore<cuda::thread_scope_device> [nr_queues];
        for (size_t i = 0; i < nr_queues; i++)
            this->locks[i].release();
    }

    __forceinline__ __device__ int
    acquire_queue() {
        //int queue = (my_lane_id() * ((get_smid() % 25) + 1)) % this->nr_queues;
        int queue = get_smid() % this->nr_queues;
        //printf("smid[%d] , lane[%d], queue[%d]\n", get_smid(), my_lane_id(), queue);
        return queue;
    }

    __forceinline__ __device__ void
    release_queue(int queue) {
    }

    __forceinline__ __device__ void
    issue_nvme_cmd(
            Controller *ctrl,
            int queue,
            nvme_ofst_t nvme_ofst,
            uint64_t ioaddr,
            uint64_t prp_list,
            size_t nr_byte,
            int hqps_block_size_log,
            uint8_t opcode,
            uint16_t *cid, uint16_t *sq_pos) {
        QueuePair* qp = &ctrl->d_qps[queue];
        nvm_cmd_t cmd;
        *cid = get_cid(&(qp->sq));

        uint64_t starting_lba = nvme_ofst >> hqps_block_size_log;
        uint64_t n_blocks = nr_byte >> hqps_block_size_log;

        nvm_cmd_header(&cmd, *cid, opcode, qp->nvmNamespace);

        uint64_t prp1, prp2;
        if (nr_byte == 4096) {
            prp1 = ioaddr;
            prp2 = 0;
        } else if (nr_byte == 8192) {
            prp1 = ioaddr;
            prp2 = ioaddr + 4096;
        } else {
            prp1 = ioaddr;
            prp2 = prp_list + 8;
        }
        nvm_cmd_data_ptr(&cmd, prp1, prp2);

        nvm_cmd_rw_blks(&cmd, starting_lba, n_blocks);
        *sq_pos = sq_enqueue(&qp->sq, &cmd);
    }

    __forceinline__ __device__ void
    poll(
            Controller *ctrl,
            int queue,
            uint16_t cid,
            uint16_t sq_pos) {
        QueuePair* qp = &ctrl->d_qps[queue];
        uint32_t cq_pos = cq_poll(&qp->cq, cid);
        cq_dequeue(&qp->cq, cq_pos, &qp->sq);
        put_cid(&qp->sq, cid);
    }


private:
    cuda::binary_semaphore<cuda::thread_scope_device> lock;
    int queue_now;
    int *cmd_count;

    int nr_queues;
    cuda::binary_semaphore<cuda::thread_scope_device> *locks;
};

struct nvme_cmd__addr {
    nvme_ofst_t nvme_ofst;
    uint64_t ioaddr;
    size_t size;
};
class CachePage_NvmeBacking: public CachePage {
public:
    __device__
    CachePage_NvmeBacking(int page_size): CachePage(page_size, nullptr, 0) { }

    DmaPtr gpu_buffer;
    uint64_t ioaddr;
    int hqps_block_size_log;

    DmaPtr prp_list__of_total_pages;

    uint64_t prp_list_ioaddr_base__of_cur_page;

    size_t max_nvme_cmds;
    size_t nr_nvme_cmds;
    FilePageId cur_filepage_id__for_nvme_cmd;
    struct nvme_cmd__addr *nvme_cmds;
    uint16_t *cids;
    uint16_t *sq_poss;

private:
    __device__ __forceinline__ nvme_ofst_t
    __get_nvmeofst(struct geminiFS_hdr *hdr, vaddr_t va) {
        uint64_t l1_idx = va >> hdr->block_bit;
        if (l1_idx < hdr->nr_l1)
            return hdr->l1[l1_idx];
        return 0;
    }

    __device__ void
    __write_back(FilePageId filepage_id, void *ctrl, void *hdr, void *queue_acquire_helper) {
        this->__xfer(filepage_id, ctrl, hdr, queue_acquire_helper, 0);
    }

    __device__ void
    __read_in(FilePageId filepage_id, void *ctrl, void *hdr, void *queue_acquire_helper) {
        this->__xfer(filepage_id, ctrl, hdr, queue_acquire_helper, 1);
    }

    __device__ __forceinline__ void
    __xfer(FilePageId filepage_id, void *ctrl_, void *hdr_, void *queue_acquire_helper_, int is_read) {
        auto *ctrl = (Controller *)ctrl_;
        auto *hdr = (struct geminiFS_hdr *)hdr_;
        auto *queue_acquire_helper = (QueueAcquireHelper *)queue_acquire_helper_;


        int page_size = this->page_size;
        int page_bit = __popc(page_size - 1);
        int file_block_size = 1 << hdr->block_bit;

        vaddr_t filepage_va = filepage_id << page_bit;
        uint64_t cachepage_ioaddr = this->ioaddr;

        int nr_file_blocks__per_page = page_size / file_block_size;

        if (filepage_id != this->cur_filepage_id__for_nvme_cmd) {
            this->nr_nvme_cmds = 0;
            this->cur_filepage_id__for_nvme_cmd = filepage_id;
            for (int idx_file_block__in_page = 0;
                    idx_file_block__in_page < nr_file_blocks__per_page;
                    idx_file_block__in_page++) {
                vaddr_t fileblock_va = filepage_va + idx_file_block__in_page * file_block_size;
                nvme_ofst_t nvme_ofst = this->__get_nvmeofst(hdr, fileblock_va);
                uint64_t ioaddr = cachepage_ioaddr + idx_file_block__in_page * file_block_size;
                if (this->nr_nvme_cmds != 0 &&
                        (this->nvme_cmds[this->nr_nvme_cmds - 1].nvme_ofst
                         + this->nvme_cmds[this->nr_nvme_cmds - 1].size
                         == nvme_ofst)) {
                    this->nvme_cmds[this->nr_nvme_cmds - 1].size += file_block_size;
                } else {
                    this->nvme_cmds[this->nr_nvme_cmds].nvme_ofst = nvme_ofst;
                    this->nvme_cmds[this->nr_nvme_cmds].ioaddr = ioaddr;
                    this->nvme_cmds[this->nr_nvme_cmds].size = file_block_size;
                    this->nr_nvme_cmds++;
                }
            }
        }

        int queue = queue_acquire_helper->acquire_queue();
        for (int cmd_idx = 0; cmd_idx < this->nr_nvme_cmds; cmd_idx++) {
            queue_acquire_helper->issue_nvme_cmd(ctrl, queue,
                    this->nvme_cmds[cmd_idx].nvme_ofst,
                    this->nvme_cmds[cmd_idx].ioaddr,
                    this->prp_list_ioaddr_base__of_cur_page,
                    this->nvme_cmds[cmd_idx].size,
                    this->hqps_block_size_log,
                    is_read ? NVM_IO_READ : NVM_IO_WRITE,
                    &(this->cids[cmd_idx]), &(this->sq_poss[cmd_idx]));
        }
        for (int cmd_idx = 0; cmd_idx < this->nr_nvme_cmds; cmd_idx++)
            queue_acquire_helper->poll(ctrl, queue, this->cids[cmd_idx], this->sq_poss[cmd_idx]);
        queue_acquire_helper->release_queue(queue);
    }
};

static Controller *ctrl;

void
host_open_all(
        const char *snvme_control_path,
        const char *snvme_path,
        const char *nvme_dev_path,
        const char *mount_path,
        uint32_t ns_id,
        uint64_t queueDepth,
        uint64_t numQueues) {
    int device;
    gpuErrchk(cudaGetDevice(&device));
    ctrl = new Controller(
            (char *)snvme_control_path,
            (char *)snvme_path,
            (char *)nvme_dev_path,
            (char *)mount_path,
            ns_id, device, queueDepth, numQueues);
}

void
host_close_all() {
    delete ctrl;
}

dev_fd_t
host_open_geminifs_file_for_device_1(
        host_fd_t host_fd,
	double cache_ratio,
        int page_size,
        int pagecache_batching_size) {
    struct geminiFS_hdr *hdr = host_fd;
    size_t file_size = hdr->virtual_space_size;
    assert(file_size % (pagecache_batching_size * page_size)== 0);
    size_t file_size__per_pagecache = file_size / pagecache_batching_size;

    size_t suggested_pagecache_capacity = file_size * cache_ratio;

    size_t pagecache_capacity;
    size_t detal = -1;
    size_t nr_pages__per_pagecache = 1;
    for (size_t nr_pages__per_pagecache = 1;
        nr_pages__per_pagecache * pagecache_batching_size * page_size < file_size;
        nr_pages__per_pagecache <<= 1) {
	size_t cur_pagecache_capacity = nr_pages__per_pagecache * pagecache_batching_size * page_size;
	size_t cur_detal = cur_pagecache_capacity < suggested_pagecache_capacity ?
		suggested_pagecache_capacity - cur_pagecache_capacity :
		cur_pagecache_capacity - suggested_pagecache_capacity;
	printf("suggested_pagecache_capacity[%llx] cur_pagecache_capacity[%llx] cur_detal[%llx]\n", suggested_pagecache_capacity, cur_pagecache_capacity, cur_detal);

	if (cur_detal < detal) {
		pagecache_capacity = cur_pagecache_capacity;
		detal = cur_detal;
	}
    }
    printf("pagecache_capacity[%llx]\n", pagecache_capacity);
    return host_open_geminifs_file_for_device(host_fd, pagecache_capacity, page_size, pagecache_batching_size);
}

dev_fd_t
host_open_geminifs_file_for_device(
        host_fd_t host_fd,
        uint64_t pagecache_capacity,
        int page_size,
        int pagecache_batching_size) {
    struct geminiFS_hdr *hdr = host_fd;

    size_t virtual_space_size = hdr->virtual_space_size;
    size_t nr_pages = pagecache_capacity / page_size;
    assert(nr_pages % pagecache_batching_size == 0);
    size_t nr_pages__per_pagecache = nr_pages / pagecache_batching_size;

    assert(virtual_space_size % pagecache_batching_size == 0);
    size_t virtual_space_size__per_pagecache =
        virtual_space_size / pagecache_batching_size;


    int file_block_size = 1 << hdr->block_bit;

    assert(file_block_size <= 128 * (1ull << 10)/*kB*/);
    assert((file_block_size <= page_size) && (page_size % file_block_size == 0));

    struct geminiFS_hdr *hdr__dev;
    gpuErrchk(cudaMallocManaged(&hdr__dev, hdr->first_block_base));
    assert((off_t)(-1) != lseek(hdr->fd, 0, SEEK_SET));
    assert(hdr->first_block_base == read(hdr->fd, hdr__dev, hdr->first_block_base));

    int nr_queues = ctrl->n_qps;
    QueueAcquireHelper *queue_acquire_helper;
    gpuErrchk(cudaMalloc(&queue_acquire_helper, sizeof(QueueAcquireHelper)));
    RUN_ON_DEVICE({
        new (queue_acquire_helper) QueueAcquireHelper (nr_queues);
    });

    int device;
    gpuErrchk(cudaGetDevice(&device));

    PageCache **pagecaches;
    gpuErrchk(cudaMalloc(&pagecaches, sizeof(PageCache *) * pagecache_batching_size));
    for (int idx_pagecache = 0;
            idx_pagecache < pagecache_batching_size;
            idx_pagecache++) {

        CachePage_NvmeBacking *cachepage_structures;
        CachePage **pages;

        gpuErrchk(cudaMallocManaged(&cachepage_structures, sizeof(CachePage_NvmeBacking) * nr_pages__per_pagecache));
        auto *the_first_cachepage = cachepage_structures + 0;

        gpuErrchk(cudaMalloc(&pages, sizeof(CachePage *) * nr_pages__per_pagecache));
        RUN_ON_DEVICE({
            for (size_t i = 0; i < nr_pages__per_pagecache; i++) {
                auto *cachepage = cachepage_structures + i;
                pages[i] = new (cachepage) CachePage_NvmeBacking (page_size);
            }
        });


        size_t max_nvme_cmds = page_size / file_block_size;
        struct nvme_cmd__addr *total_nvme_cmds;
        uint16_t *total_cids;
        uint16_t *total_sq_poss;
        gpuErrchk(cudaMalloc(&total_nvme_cmds, sizeof(struct nvme_cmd__addr) * max_nvme_cmds * nr_pages__per_pagecache));
        gpuErrchk(cudaMalloc(&total_cids, sizeof(uint16_t) * max_nvme_cmds * nr_pages__per_pagecache));
        gpuErrchk(cudaMalloc(&total_sq_poss, sizeof(uint16_t) * max_nvme_cmds * nr_pages__per_pagecache));

        the_first_cachepage->gpu_buffer = createDma(ctrl->ctrl, page_size * nr_pages__per_pagecache, device);

        uint64_t total_buf_va_base = (uint64_t)the_first_cachepage->gpu_buffer->vaddr;
        uint64_t total_buf_ioaddr_base = the_first_cachepage->gpu_buffer->ioaddrs[0];
        for (size_t i = 0; i < nr_pages__per_pagecache; i++) {
            auto *cachepage = cachepage_structures + i;
            cachepage->buf = (void *)(total_buf_va_base + i * page_size);
            cachepage->ioaddr = total_buf_ioaddr_base + i * page_size;
            cachepage->hqps_block_size_log = ctrl->h_qps[0]->block_size_log;

            cachepage->max_nvme_cmds = max_nvme_cmds;
            cachepage->nr_nvme_cmds = 0;
            cachepage->cur_filepage_id__for_nvme_cmd = -1;

            cachepage->nvme_cmds = total_nvme_cmds + max_nvme_cmds * i;
            cachepage->cids = total_cids + max_nvme_cmds * i;
            cachepage->sq_poss = total_sq_poss + max_nvme_cmds * i;
        }

        size_t nvme_page_size = ctrl->ctrl->page_size;
        size_t nr_nvme_pages__per_page = page_size / nvme_page_size;
        size_t nr_nvme_pages = nr_nvme_pages__per_page * nr_pages__per_pagecache;
        the_first_cachepage->prp_list__of_total_pages = createDma(ctrl->ctrl,
                sizeof(uint64_t) * nr_nvme_pages,
                device);
        uint64_t *dev_ptr__ioaddrs = (uint64_t *)the_first_cachepage->prp_list__of_total_pages->vaddr;
        uint64_t total_prp_list__ioaddr_base = the_first_cachepage->prp_list__of_total_pages->ioaddrs[0];

        RUN_ON_DEVICE({
            for (size_t idx_page = 0; idx_page < nr_pages__per_pagecache; idx_page++) {
                auto *cachepage = cachepage_structures + idx_page;
                auto page_ioaddr_base = cachepage->ioaddr;
                for (size_t idx_nvme_page__in_page = 0;
                        idx_nvme_page__in_page < nr_nvme_pages__per_page;
                        idx_nvme_page__in_page++) {
                    dev_ptr__ioaddrs[idx_page * nr_nvme_pages__per_page + idx_nvme_page__in_page] = 
                    page_ioaddr_base + idx_nvme_page__in_page * nvme_page_size;
                }
                cachepage->prp_list_ioaddr_base__of_cur_page = total_prp_list__ioaddr_base + sizeof(uint64_t) * idx_page * nr_nvme_pages__per_page;
            }
        });

        PageCache *pagecache = __internal__get_pagecache(
                nr_pages__per_pagecache * page_size,
                page_size,
                virtual_space_size__per_pagecache,
                pages,
                nr_queues,
                ctrl->d_ctrl_ptr, hdr__dev, queue_acquire_helper);
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

class CachePage_TestForPageCache: public CachePage {
public:
    __device__
    CachePage_TestForPageCache(int page_size): CachePage(page_size, nullptr, 0) { }
private:
    __device__ void
    __write_back(FilePageId filepage_id, void *ctrl, void *hdr, void *queue_acquire_helper) {
        this->__xfer(filepage_id, ctrl, hdr, queue_acquire_helper, 1);
        printf("filepage_id[%llx] write back\n", filepage_id);
    }

    __device__ void
    __read_in(FilePageId filepage_id, void *ctrl, void *hdr, void *queue_acquire_helper) {
        this->__xfer(filepage_id, ctrl, hdr, queue_acquire_helper, 0);
        printf("filepage_id[%llx] read in\n", filepage_id);
    }

    __device__ __forceinline__ void
    __xfer(FilePageId filepage_id, void *ctrl_, void *hdr_, void *queue_acquire_helper_, int is_read) {
        auto *queue_acquire_helper = (QueueAcquireHelper *)queue_acquire_helper_;


        int queue = queue_acquire_helper->acquire_queue();
        //__nanosleep(1000);
        queue_acquire_helper->release_queue(queue);

    }
};

dev_fd_t
host_get_pagecache__for_test_evicting(
        uint64_t fake_file_size,
        uint64_t pagecache_capacity,
        int page_size,
        int pagecache_batching_size) {
    size_t virtual_space_size = fake_file_size;
    size_t nr_pages = pagecache_capacity / page_size;
    assert(nr_pages % pagecache_batching_size == 0);
    size_t nr_pages__per_pagecache = nr_pages / pagecache_batching_size;

    assert(virtual_space_size % pagecache_batching_size == 0);
    size_t virtual_space_size__per_pagecache =
        virtual_space_size / pagecache_batching_size;

    int nr_queues = 32;
    QueueAcquireHelper *queue_acquire_helper;
    gpuErrchk(cudaMalloc(&queue_acquire_helper, sizeof(QueueAcquireHelper)));
    RUN_ON_DEVICE({
        new (queue_acquire_helper) QueueAcquireHelper (nr_queues);
    });

    PageCache **pagecaches;
    gpuErrchk(cudaMalloc(&pagecaches, sizeof(PageCache *) * pagecache_batching_size));
    for (int idx_pagecache = 0;
            idx_pagecache < pagecache_batching_size;
            idx_pagecache++) {
        uint8_t *all_raw_pages;
        CachePage_TestForPageCache *cachepage_structures;
        CachePage **pages;

        gpuErrchk(cudaMalloc(&all_raw_pages, nr_pages__per_pagecache * page_size));
        gpuErrchk(cudaMallocManaged(&cachepage_structures, nr_pages__per_pagecache * sizeof(CachePage_TestForPageCache)));
        gpuErrchk(cudaMalloc(&pages, nr_pages__per_pagecache * sizeof(CachePage *)));

        RUN_ON_DEVICE({
            for (size_t i = 0; i < nr_pages__per_pagecache; i++) {
                auto *cachepage = cachepage_structures + i;
                pages[i] = new (cachepage) CachePage_TestForPageCache (page_size);
                cachepage->buf = all_raw_pages + i * page_size;
            }
        });
        PageCache *pagecache =  __internal__get_pagecache(
                nr_pages__per_pagecache * page_size,
                page_size,
                virtual_space_size__per_pagecache,
                pages,
                nr_queues,
                nullptr, nullptr, queue_acquire_helper);
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
