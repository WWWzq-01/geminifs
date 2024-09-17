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



#define my_assert(code) do { \
    if (!(code)) { \
        host_close_all(); \
        assert(0); \
    } \
} while(0)


#define snvme_control_path "/dev/snvm_control"
#define snvme_path "/dev/snvme1"
#define nvme_mount_path "/home/qs/nvm_mount"
#define nvme_dev_path "/dev/nvme0n1"


#define geminifs_file_name "checkpoint.geminifs"
#define geminifs_file_path (nvme_mount_path "/" geminifs_file_name)
#define MAX_READ_IO_NUM (10000)
#define MAX_TRIALS (10000)
#define io_size  1024*4
 __device__ void
read_from_nvme(QueuePair* qp,uint64_t start_block, uint64_t dev_buf[],uint64_t n_blks ,uint64_t entry) {

    // int *buf = (int *)dev_buf[0];
    // for (size_t i = 0; i < 256; i++)
    //     buf[i] = i;
        
        // https://www.cnblogs.com/ingram14/p/15778938.html 参考这个
        // prp 有三种模式
        // 第一种 数据长度= 1 page_size <= 4k, prp1=dev_buf[0] nvm_cmd_rw_blk中长度为8
        nvm_cmd_t cmd;

        uint16_t cid = get_cid(&(qp->sq)); 
        // printf("access_data 0 cid: %u\n", (unsigned int) cid);
        nvm_cmd_header(&cmd, cid, NVM_IO_READ, qp->nvmNamespace);

        uint64_t prp1 = dev_buf[entry];
        uint64_t prp2 = 0;
        nvm_cmd_data_ptr(&cmd, prp1, prp2);
        nvm_cmd_rw_blks(&cmd, start_block, n_blks); // 128KB
        uint16_t sq_pos = sq_enqueue(&qp->sq, &cmd);
        // printf ("access_data 1 , sq_pos is %u\n",sq_pos);
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

__device__ void
write_to_nvme(QueuePair* qp,uint64_t start_block, void *dev_buf, uint64_t blk_num, int queue) {
}

__device__ void
sync_nvme(nvme_ofst_t nvme_ofst) {
}

// __global__ void
// read_from_nvme__using_device(Controller* ctrl,uint64_t start_block, uint64_t *dev_buf, uint64_t n_blocks, int queue) {


//     read_from_nvme(&ctrl->d_qps[queue], start_block, dev_buf, n_blocks);

// }

// __global__ void
// read_from_nvme__using_device_prp(Controller* ctrl,uint64_t start_block, uint64_t *dev_buf, uint64_t n_blocks, int queue) {


//     read_from_nvme(&ctrl->d_qps[queue], start_block, dev_buf, n_blocks);

// }
__global__ void
seq_read_test(Controller* ctrl, uint64_t *ioaddr_list, uint64_t *nvme_off_list, int queue_num,int inter_iter) {
    uint32_t j = 0;
    uint64_t tid = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t queue  = (tid/4) % queue_num;
    uint64_t start_block = nvme_off_list[tid] >> ctrl->d_qps[queue].block_size_log;
    uint64_t n_blocks = io_size >> ctrl->d_qps[queue].block_size_log;
    // printf("tid is %lu,ioaddr_list is %lx . start_block is %lx,n_blocks is %lu\n",tid,ioaddr_list[tid],start_block,n_blocks);
    for(j=0; j< inter_iter;j++)
    {
        read_from_nvme(&ctrl->d_qps[queue], start_block,ioaddr_list, n_blocks,tid);
    }
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
main(int argc, char **argv) {

	if (argc < 5)
	{
		fprintf(stderr, "<iterations> <inter_iterations> <blocks> <threads> io_size(optional, default: 4096)\n");
		return -1;
	}

    Controller *ctrl;
	double iterations = atoi(argv[1]);
    double inter_iterations = atoi(argv[1]);
	assert(iterations <= MAX_TRIALS);
	int nblocks = atoi(argv[3]);
	int nthreads = atoi(argv[4]);
    double memSize = io_size * nblocks * nthreads;
    int req_num = nblocks * nthreads;
    int device;
    int num_queue = 32;
    int block_size = 1024*64;
    
    uint32_t cudaDevice = 0;
    void *buf__host = NULL;
    int *buf__host_int = NULL;
    int ret,fd;
    DmaPtr      gpu_buffer;

    size_t i;
    struct nds_mapping mapping;
    nvme_ofst_t nvme_ofst;
    cuda_err_chk(cudaSetDevice(cudaDevice));
    ctrl = new Controller(snvme_control_path,snvme_path,nvme_dev_path,nvme_mount_path,1,0,1024,num_queue);


    // int *buf__dev;
    // assert(cudaSuccess ==
    //         cudaMalloc(&buf__dev, block_size));

    gpu_buffer = createDma(ctrl->ctrl, NVM_PAGE_ALIGN((int)memSize, 1UL << 16), cudaDevice);
    
    printf("n_ioaddrs: %u, gpu buffer pagesize:%u \n", gpu_buffer.get()->n_ioaddrs, gpu_buffer.get()->page_size);
    uint64_t* h_ioaddrs = new uint64_t[req_num];

    int iter_per_io = io_size / 4096;
    for (size_t i = 0; (i <req_num) ; i++) {
        if(gpu_buffer.get()->ioaddrs[i]!=NULL)
        {
            h_ioaddrs[i] = (uint64_t)gpu_buffer.get()->ioaddrs[i*iter_per_io];
            // printf("h_ioaddrs is %lx\n", h_ioaddrs[i]);
        }
    }
    uint64_t* d_ioaddrs;

    cuda_err_chk(cudaMalloc(&d_ioaddrs, req_num*sizeof(uint64_t)));
    cuda_err_chk(cudaMemcpy(d_ioaddrs, h_ioaddrs, req_num*sizeof(uint64_t), cudaMemcpyHostToDevice));
    
    uint64_t* h_nvme_off = new uint64_t[req_num]; 
    for (size_t i = 0; (i < req_num) ; i++) {
        h_nvme_off[i] = 0x100000000 + i * io_size;
        // printf("h_ioaddrs is %lx\n", h_nvme_off[i]);
    }
    uint64_t* d_nvme_off;
    cuda_err_chk(cudaMalloc(&d_nvme_off, req_num*sizeof(uint64_t)));
    cuda_err_chk(cudaMemcpy(d_nvme_off, h_nvme_off, req_num*sizeof(uint64_t), cudaMemcpyHostToDevice));

    GpuTimer gputimer;
    gputimer.Start();
    for (size_t i = 0; i < iterations ; i++) {       
        seq_read_test<<<nthreads, nblocks>>>((Controller*)ctrl->d_ctrl_ptr,d_ioaddrs,d_nvme_off,num_queue,(int)inter_iterations);

    }
    gputimer.Stop();
    cudaDeviceSynchronize();
    double elapsed = gputimer.Elapsed()/1000; // s
    double bw = ((memSize*inter_iterations*iterations)/(double)(1024*1024) ) / (elapsed);
    std::cout << "time:" << elapsed << "s " << "bw:" << bw << "MB per s" << std::endl;
      
   

    // uint64_t start_block = nvme_ofst >> ctrl->h_qps[0]->block_size_log;
    // uint64_t n_blocks=  4096 >> ctrl->h_qps[0]->block_size_log ;
    // int iiii = 0;


    // read_from_nvme__using_device_prp<<<1, 1>>>((Controller*)ctrl->d_ctrl_ptr,start_block, tempd, n_blocks, 0);
    // cudaDeviceSynchronize();


out:
    delete(ctrl);
    return 0;
}
