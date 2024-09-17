
#ifndef __BENCHMARK_CTRL_H__
#define __BENCHMARK_CTRL_H__

// #ifndef __CUDACC__
// #define __device__
// #define __host__
// #endif

#include <cstdint>
#include "buffer.h"
#include "nvm_types.h"
#include "nvm_ctrl.h"
#include "nvm_aq.h"
#include "nvm_admin.h"
#include "nvm_util.h"
#include "nvm_error.h"
#include <string>
#include <memory>
#include <vector>
#include <stdexcept>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <unistd.h>
#include <fcntl.h>
#include <cstdlib>
#include <algorithm>
#include <simt/atomic>
#include "../file.h"
#include "queue.h"

#define MAX_QUEUES 1024
#define NVM_CTRL_IOQ_MINNUM    64

struct Controller
{
    simt::atomic<uint64_t, simt::thread_scope_device> access_counter;
    nvm_ctrl_t*             ctrl;
    struct nvm_ctrl_info    info;
    struct nvm_ns_info      ns;
    struct disk             disk;
    uint16_t                n_sqs;
    uint16_t                n_cqs;
    uint16_t                n_qps;
    uint16_t                n_user_qps;

    uint32_t                deviceId;
    QueuePair**             h_qps;
    QueuePair*              d_qps;


    simt::atomic<uint64_t, simt::thread_scope_device> queue_counter;

    uint32_t page_size;
    uint32_t blk_size;
    uint32_t blk_size_log;
    char* dev_path;
    char* dev_mount_path;

    void* d_ctrl_ptr;
    BufferPtr d_ctrl_buff;

    // Controller(const char* path, uint32_t nvmNamespace, uint32_t cudaDevice, uint64_t queueDepth, uint64_t numQueues);
    Controller::Controller(const char* snvme_control_path, const char* snvme_path, char* nvme_dev_path,char* mount_path, uint32_t ns_id, uint32_t cudaDevice, uint64_t queueDepth, uint64_t numQueues);


    void print_reset_stats(void);

    ~Controller();
};



using error = std::runtime_error;
using std::string;


inline void Controller::print_reset_stats(void) {
    cuda_err_chk(cudaMemcpy(&access_counter, d_ctrl_ptr, sizeof(simt::atomic<uint64_t, simt::thread_scope_device>), cudaMemcpyDeviceToHost));
    std::cout << "------------------------------------" << std::endl;
    std::cout << std::dec << "#SSDAccesses:\t" << access_counter << std::endl;

    cuda_err_chk(cudaMemset(d_ctrl_ptr, 0, sizeof(simt::atomic<uint64_t, simt::thread_scope_device>)));
}





inline Controller::Controller(const char* snvme_control_path, const char* snvme_path, char* nvme_dev_path,char* mount_path, uint32_t ns_id, uint32_t cudaDevice, uint64_t queueDepth, uint64_t numQueues)
    : ctrl(nullptr)
    , deviceId(cudaDevice)
{
    int status;
    int snvme_c_fd = open(snvme_control_path, O_RDWR);
    if (snvme_c_fd < 0)
    {
        throw error(string("Failed to open descriptor: ") + strerror(errno));
    }
    int snvme_d_fd = open(snvme_path, O_RDWR);
    if (snvme_d_fd < 0)
    {
        throw error(string("Failed to open descriptor: ") + strerror(errno));
    }
    /************Step 1 mmap pci bar 0 and prepare user defined queue***************/
    // Get controller reference
    status = nvm_ctrl_init(&ctrl, snvme_c_fd,snvme_d_fd);
    if (!nvm_ok(status))
    {
        throw error(string("Failed to get controller reference: ") + nvm_strerror(status));
    }

    close(snvme_c_fd);
    close(snvme_d_fd);

    ctrl->on_host = 0;

    // initializeController(*this, ns_id);
    cudaError_t err = cudaHostRegister((void*) ctrl->mm_ptr, NVM_CTRL_MEM_MINSIZE, cudaHostRegisterIoMemory); //UVM
    if (err != cudaSuccess)
    {
        throw error(string("Unexpected error while mapping IO memory (cudaHostRegister): ") + cudaGetErrorString(err));
    }
    // queue_counter = 0;
    // page_size = ctrl->page_size;
    // blk_size = this->ns.lba_data_size;
    // blk_size_log = std::log2(blk_size);
   
    // n_qps = std::min(n_sqs, n_cqs);
    // n_qps = std::min(n_qps, (uint16_t)numQueues);
    uint16_t max_queue = 75;
    n_qps = std::min(max_queue, (uint16_t)numQueues);
    n_sqs = n_qps;
    n_cqs = n_qps;
    printf("SQs: %d\tCQs: %d\tn_qps: %d\n", n_sqs, n_cqs, n_qps);
    ctrl->cq_num = n_cqs;
    ctrl->sq_num = n_cqs;

    // set the user defined io queues num, and located on device
    status = ioctl_set_qnum(ctrl, n_sqs+n_cqs);
    if (status!=0)
    {
        throw error(string("Failed to set user io queue num: ") + nvm_strerror(status));
    }

    h_qps = (QueuePair**) malloc(sizeof(QueuePair)*n_qps);
    cuda_err_chk(cudaMalloc((void**)&d_qps, sizeof(QueuePair)*n_qps));

    for (size_t i = 0; i < n_qps; i++) {
        //printf("started creating qp\n");
        h_qps[i] = new QueuePair(ctrl, cudaDevice,i, queueDepth);
        
        // cuda_err_chk(cudaMemcpy(d_qps+i, h_qps[i], sizeof(QueuePair), cudaMemcpyHostToDevice));
    }
    //printf("finished creating all qps\n");


    
    /************Step 2 Reg the SNVMe using prepared the user Queue***************/
    status =  ioctl_use_userioq(ctrl,1);
    if (status != 0)
    {
        throw error(string("Failed to set ioctl_use_userioq : ") + nvm_strerror(status));
    }

    status =  ioctl_reg_nvme(ctrl,1);
    if (status != 0)
    {
        throw error(string("Failed to set ioctl reg snvme : ") + nvm_strerror(status));
    }
    sleep(5);
     /************Step 3 init the user defined queue Queue***************/
    
    //user queue init
    disk.ns_id = ns_id; // default each disk allocate one namespace
    status =  init_userioq_device(ctrl,h_qps,&disk);
    if (status != 0)
    {
        throw error(string("Failed to set ioctl reg snvme : ") + nvm_strerror(status));
    }

    for (size_t i = 0; i < n_qps; i++) {
        
        void* devicePtr = nullptr;
        cudaError_t err = cudaHostGetDevicePointer(&devicePtr, (void*) h_qps[i]->cq.db, 0);
        if (err != cudaSuccess)
        {
            throw error(string("Failed to get device pointer") + cudaGetErrorString(err));
        }
        h_qps[i]->cq.db = (volatile uint32_t*) devicePtr;

        // Get a valid device pointer for SQ doorbell
        err = cudaHostGetDevicePointer(&devicePtr, (void*) h_qps[i]->sq.db, 0);
        if (err != cudaSuccess)
        {
            throw error(string("Failed to get device pointer") + cudaGetErrorString(err));
        }
        h_qps[i]->sq.db = (volatile uint32_t*) devicePtr;
        
        cuda_err_chk(cudaMemcpy(d_qps+i, h_qps[i], sizeof(QueuePair), cudaMemcpyHostToDevice));
        // printf("finished creating qp, addr is %lx , cuda addr is %lx\n",h_qps[i],d_qps+i);
    }
    
    page_size = ctrl->page_size;
    blk_size = disk.block_size;
    blk_size_log = std::log2(blk_size);

    dev_path = nvme_dev_path;
    dev_mount_path = mount_path;

    d_ctrl_buff = createBuffer(sizeof(Controller), cudaDevice);
    d_ctrl_ptr = d_ctrl_buff.get();
    cuda_err_chk(cudaMemcpy(d_ctrl_ptr, this, sizeof(Controller), cudaMemcpyHostToDevice));

    Host_file_system_int(dev_path,dev_mount_path);
}



inline Controller::~Controller()
{
    
    cudaFree(d_qps);
    for (size_t i = 0; i < n_qps; i++) {
        delete h_qps[i];
    }
    
    free(h_qps);
    int ret = Host_file_system_exit(dev_path);
    if(ret < 0)
        exit(-1);
    printf("Controller realease\n");
    nvm_ctrl_free(ctrl);

}






#endif
