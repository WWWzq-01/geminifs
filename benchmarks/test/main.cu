#include <iostream>
#include <cassert>
#include <cstddef>
#include <cstdlib>  
#include <stdio.h>
#include <assert.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include "ctrl.h"
#include <cuda_runtime.h>

#include "get-offset/get-offset.h"
#include "geminifs.h"
#include <buffer.h>
#include <queue.h>
#include <nvm_parallel_queue.h>
#include <nvm_types.h>
#include <nvm_util.h>
#include <nvm_cmd.h>
#define snvme_helper_path "/dev/snvme_helper"
#define snvme_control_path "/dev/snvm_control"
#define snvme_path "/dev/snvme1"
#define nvme_mount_path "/home/qs/nvm_mount"
#define nvme_dev_path "/dev/nvme0n1"
 __device__ void
read_from_nvme(QueuePair* qp,uint64_t start_block, uint64_t dev_buf[], uint64_t blk_num) {

    // int *buf = (int *)dev_buf[0];
    // for (size_t i = 0; i < 256; i++)
    //     buf[i] = i;
    
    for (size_t iii = 0; iii < 2048; iii++) {
        nvm_cmd_t cmd;

        uint16_t cid = get_cid(&(qp->sq)); 
        // printf("access_data 0 cid: %u\n", (unsigned int) cid);
        nvm_cmd_header(&cmd, cid, NVM_IO_READ, qp->nvmNamespace);

        uint64_t prp1 = dev_buf[0];
        uint64_t prp2 = 0;
        nvm_cmd_data_ptr(&cmd, prp1, prp2);
        nvm_cmd_rw_blks(&cmd, start_block, blk_num); // 128KB
        uint16_t sq_pos = sq_enqueue(&qp->sq, &cmd);
        // printf ("access_data 1 , sq_pos is %u\n",sq_pos);
        uint32_t head, head_;
        // uint64_t pc_pos;
        // uint64_t pc_prev_head;

        uint32_t cq_pos = cq_poll(&qp->cq, cid);
        // printf ("access_data 2 , sq_pos is %u\n",cq_pos);
        // qp->cq.tail.fetch_add(1, simt::memory_order_acq_rel);
        // // pc_prev_head = pc->q_head->load(simt::memory_order_relaxed);
        // // pc_pos = pc->q_tail->fetch_add(1, simt::memory_order_acq_rel);
        
        cq_dequeue(&qp->cq, cq_pos, &qp->sq);
        // printf ("access_data 3 \n");

        put_cid(&qp->sq, cid);
        // printf ("access_data 4 \n");
    }

}

__device__ void
write_to_nvme(QueuePair* qp,uint64_t start_block, void *dev_buf, uint64_t blk_num, int queue) {
}

__device__ void
sync_nvme(nvme_ofst_t nvme_ofst) {
}

__global__ void
read_from_nvme__using_device(Controller* ctrl,uint64_t start_block, uint64_t *dev_buf, uint64_t n_blocks, int queue) {


    read_from_nvme(&ctrl->d_qps[queue], start_block, dev_buf, n_blocks);

}

__global__ void
write_to_nvme__using_device(QueuePair* qp,nvme_ofst_t nvme_ofst, void *dev_buf, uint64_t len, int queue) {
    uint64_t start_block = nvme_ofst >> qp->block_size_log;
    uint64_t n_blocks=  len >> qp->block_size_log ;

    write_to_nvme(qp,start_block, dev_buf, n_blocks, queue);
}

__global__ void
sync_nvme__using_device(nvme_ofst_t nvme_ofst) {
    sync_nvme(nvme_ofst);
}

int
main () {
    std::cout << "halo" << std::endl;
    Controller *ctrl;
    int block_size = 1024*64;

    uint32_t cudaDevice = 0;
    void *buf__host = NULL;
    int *buf__host_int = NULL;
    int ret,fd;
    DmaPtr      gpu_buffer;
    const char *filename = "/home/qs/nvm_mount/test.data";
    size_t i;
    struct nds_mapping mapping;
    nvme_ofst_t nvme_ofst;
    cuda_err_chk(cudaSetDevice(cudaDevice));
    ctrl = new Controller(snvme_control_path,snvme_path,nvme_dev_path,nvme_mount_path,1,0,1024,32);


    fd = open(filename, O_RDWR| O_CREAT | O_DIRECT , S_IRUSR | S_IWUSR);
    assert(0 <= fd);
    assert(0 == ftruncate(fd, block_size*16));
    
    ret = posix_memalign(&buf__host, 4096, block_size); //92d96858000
    assert(ret==0);
    buf__host_int = (int*)buf__host;
    for (i = 0; i < block_size / sizeof(int); i++)
        buf__host_int[i] = i;
    assert(block_size == pwrite(fd, buf__host_int, block_size,block_size));
    fsync(fd);

    int snvme_helper_fd = open(snvme_helper_path, O_RDWR);
    if (snvme_helper_fd < 0) {
        perror("Failed to open snvme_helper_fd");
        assert(0);
    }

    mapping.file_fd = fd;
    mapping.offset = block_size;
    mapping.len = block_size;
    if (ioctl(snvme_helper_fd, SNVME_HELP_GET_NVME_OFFSET, &mapping) < 0) {
        perror("ioctl failed");
        assert(0);
    }
    nvme_ofst = mapping.address;
    close(snvme_helper_fd);
    close(fd);

    printf("nvme_ofst is %lx,block size is %u\n",nvme_ofst,block_size);
    // int *buf__dev;
    // assert(cudaSuccess ==
    //         cudaMalloc(&buf__dev, block_size));

    gpu_buffer = createDma(ctrl->ctrl, NVM_PAGE_ALIGN(block_size, 1UL << 16), cudaDevice);

    uint64_t* temp = new uint64_t[gpu_buffer.get()->n_ioaddrs];
    for (size_t i = 0; (i < gpu_buffer.get()->n_ioaddrs) ; i++) {
        if(gpu_buffer.get()->ioaddrs[i]!=NULL)
        {
            
            temp[i] = (uint64_t)gpu_buffer.get()->ioaddrs[i];
            // printf("temp addr %d  %lx \n", i,   temp[i]);
        }
    //     temp[i] = (uint64_t)gpu_buffer.get()->ioaddrs[i];
    //     printf("temp addr %d  %lx ", i,   (uint64_t)gpu_buffer.get()->ioaddrs[i]);
    }
    uint64_t* tempd;
    cuda_err_chk(cudaMalloc(&tempd, gpu_buffer.get()->n_ioaddrs * sizeof(uint64_t)));

     
    cuda_err_chk(cudaMemcpy(tempd, temp, gpu_buffer.get()->n_ioaddrs * sizeof(uint64_t), cudaMemcpyHostToDevice));
    
    // only use the first prp1_buf[0]
    printf("ctrl->d_qps addr is %lx\n",ctrl->d_qps);

    uint64_t start_block = nvme_ofst >> ctrl->h_qps[0]->block_size_log;
    uint64_t n_blocks=  4096 >> ctrl->h_qps[0]->block_size_log ;
    int iiii = 0;

    read_from_nvme__using_device<<<1, 1>>>((Controller*)ctrl->d_ctrl_ptr,start_block, tempd, n_blocks, 0);
    cudaDeviceSynchronize();


    // printf("gpu vaddr is %lx, dma addr is is %lx\n",gpu_buffer.get()->vaddr,gpu_buffer.get()->ioaddrs[0]);
    // void *buf__host2 = NULL;
    // ret = posix_memalign(&buf__host2, 4096, block_size); 
    // assert(ret==0);
    
    // ret = cudaMemcpy(buf__host2, gpu_buffer.get()->vaddr, 4096, cudaMemcpyDeviceToHost);
    // int *buf__host2_int = (int*)buf__host2;
    // if(ret!=cudaSuccess)
    // {
    //     printf("mem copy fail, ret is %d\n",ret);
    //     goto out;
    // }
    // printf("\n");
    // for (size_t i = 0; i < 256; i++)
    // {
        
    //     printf("%d",buf__host2_int[i]);
  
    // }
    // printf("\n");
    
    //     assert(buf__host[i] == i);

    // for (size_t i = 0; i < block_size / sizeof(int); i++)
    //     buf__host[i] = i + 1;
    // assert(cudaSuccess ==
    //         cudaMemcpy(buf__dev, buf__host, block_size, cudaMemcpyHostToDevice));
    // write_to_nvme__using_device<<<1, 1>>>(nvme_ofst, buf__dev, block_size, 0);
    // sync_nvme__using_device<<<1, 1>>>(nvme_ofst);

    // fd = open(filename, O_RDWR);
    // assert(0 <= fd);

    // assert(block_size == read(fd, buf__host, block_size));
    // for (size_t i = 0; i < block_size / sizeof(int); i++)
    //     std::cout << i << std::endl;
    // for (size_t i = 0; i < block_size / sizeof(int); i++)
    //     assert(buf__host[i] == i + 1);

    // close(fd);

out:
    delete(ctrl);
    return 0;
}
