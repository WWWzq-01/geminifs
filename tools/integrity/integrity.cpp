#include <nvm_types.h>
#include <nvm_ctrl.h>
#include <nvm_dma.h>
#include <nvm_aq.h>
#include <nvm_admin.h>
#include <nvm_error.h>
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdbool.h>
#include <getopt.h>
#include <string.h>
#include <errno.h>


#include <fcntl.h>
#include <unistd.h>

#include "get-offset/get-offset.h"
#include "integrity.h"
#include "read.h"
#include "../../src/file.h"

#define snvme_control_path "/dev/snvm_control"
#define snvme_path "/dev/snvme1"
#define nvme_dev_path "/dev/nvme0n1"
#define snvme_helper_path "/dev/snvme_helper"
#define nvme_mount_path "/home/qs/nvm_mount"
struct arguments
{
    uint64_t        device_id;
    const char*     device_path;
    uint32_t        ns_id;
    uint16_t        n_queues;
    uint64_t        read_bytes;
    const char*     filename;
    const char*     device_control_path;
    
};



static bool parse_number(uint64_t* number, const char* str, int base, uint64_t lo, uint64_t hi)
{
    char* endptr = NULL;
    uint64_t ul = strtoul(str, &endptr, base);

    if (endptr == NULL || *endptr != '\0')
    {
        return false;
    }

    if (lo < hi && (ul < lo || ul >= hi))
    {
        return false;
    }

    *number = ul;
    return true;
}



static void parse_arguments(int argc, char** argv, struct arguments* args)
{
    struct option opts[] = {
        { "help", no_argument, NULL, 'h' },
        { "read", required_argument, NULL, 'r' },
        { "ctrl", required_argument, NULL, 'c' },
        { "namespace", required_argument, NULL, 'n' },
        { "queues", required_argument, NULL, 'q' },
        { "device_control_path", required_argument, NULL, 'p' },
        { "device_chr_path", required_argument, NULL, 'd' },
        { NULL, 0, NULL, 0 }
    };

    int opt;
    int idx;
    uint64_t num;

    args->device_id = 0;
    args->device_path = NULL;
    args->ns_id = 1;
    args->n_queues = 1;
    args->read_bytes = 0;
    args->filename = NULL;
    args->device_control_path = NULL;
  

    while ((opt = getopt_long(argc, argv, ":hr:c:n:q:p:d", opts, &idx)) != -1)
    {
        switch (opt)
        {
            case '?': // unknown option
            default:
                fprintf(stderr, "Unknown option: `%s'\n", argv[optind - 1]);
                exit(4);

            case ':': // missing option argument
                fprintf(stderr, "Missing argument for option `%s'\n", argv[optind - 1]);
                exit(4);

            case 'h':
                fprintf(stderr, "Usage: %s --ctrl=device-path [--read=bytes] [-n namespace] [-q queues] filename\n", argv[0]);
                exit(4);

            case 'r':
                if ( !parse_number(&args->read_bytes, optarg, 0, 0, 0) || args->read_bytes == 0 )
                {
                    fprintf(stderr, "Invalid number of bytes: `%s'\n", optarg);
                    exit(1);
                }
                break;

            case 'c': // device identifier
                args->device_path = optarg;
                break;
    
            case 'n': // specify namespace number
                if (! parse_number(&num, optarg, 0, 0, 0) )
                {
                    fprintf(stderr, "Invalid controller identifier: `%s'\n", optarg);
                    exit(3);
                }
                args->ns_id = (uint32_t) num;
                break;

            case 'q': // set number of queues
                if (! parse_number(&num, optarg, 0, 1, 0xffff) )
                {
                    fprintf(stderr, "Invalid number of queues: `%s'\n", optarg);
                    exit(3);
                }
                args->n_queues = (uint16_t) num;
                break;
        }
    }

    argc -= optind;
    argv += optind;


    if (args->device_path == NULL)
    {
        fprintf(stderr, "No controller specified!\n");
        exit(1);
    }


    if (argc < 1)
    {
        fprintf(stderr, "File not specified!\n");
        exit(2);
    }
    else if (argc > 1)
    {
        fprintf(stderr, "More than one filename specified!\n");
        exit(2);
    }

    args->filename = argv[0];
}


static void print_ctrl_info(FILE* fp, const struct nvm_ctrl_info* info)
{
    unsigned char vendor[4];
    memcpy(vendor, &info->pci_vendor, sizeof(vendor));

    char serial[21];
    memset(serial, 0, 21);
    memcpy(serial, info->serial_no, 20);

    char model[41];
    memset(model, 0, 41);
    memcpy(model, info->model_no, 40);

    char revision[9];
    memset(revision, 0, 9);
    memcpy(revision, info->firmware, 8);

    fprintf(fp, "------------- Controller information -------------\n");
    fprintf(fp, "PCI Vendor ID           : %x %x\n", vendor[0], vendor[1]);
    fprintf(fp, "PCI Subsystem Vendor ID : %x %x\n", vendor[2], vendor[3]);
    fprintf(fp, "NVM Express version     : %u.%u.%u\n",
            info->nvme_version >> 16, (info->nvme_version >> 8) & 0xff, info->nvme_version & 0xff);
    fprintf(fp, "Controller page size    : %zu\n", info->page_size);
    fprintf(fp, "Max queue entries       : %u\n", info->max_entries);
    fprintf(fp, "Serial Number           : %s\n", serial);
    fprintf(fp, "Model Number            : %s\n", model);
    fprintf(fp, "Firmware revision       : %s\n", revision);
    fprintf(fp, "Max data transfer size  : %zu\n", info->max_data_size);
    fprintf(fp, "Max outstanding commands: %zu\n", info->max_out_cmds);
    fprintf(fp, "Max number of namespaces: %zu\n", info->max_n_ns);
    fprintf(fp, "--------------------------------------------------\n");
}







static void remove_queues(struct queue* queues, uint16_t n_queues)
{
    uint16_t i;

    if (queues != NULL)
    {

        for (i = 0; i < n_queues; i++)
        {
            remove_queue(&queues[i]);
        }

        free(queues);
    }
}



static int request_queues(nvm_ctrl_t* ctrl, struct queue** queues)
{
    struct queue* q;
    *queues = NULL;
    uint16_t i;
    int status;
    ctrl->on_host = 1;
    status = ioctl_set_qnum(ctrl, ctrl->cq_num+ctrl->sq_num);
    if (status != 0)
    {
    
        return status;
    }
    // Allocate queue descriptors
    q = (queue *)calloc(ctrl->cq_num+ctrl->sq_num, sizeof(struct queue));
    if (q == NULL)
    {
        fprintf(stderr, "Failed to allocate queues: %s\n", strerror(errno));
        return ENOMEM;
    }

    // Create completion queue
    for (i = 0; i < ctrl->cq_num; ++i)
    {
        status = create_queue(&q[i], ctrl, NULL, i);
        if (status != 0)
        {
            free(q);
            return status;
        }
    }


    // Create submission queues
    for (i = 0; i < ctrl->sq_num; ++i)
    {
        status = create_queue(&q[i + ctrl->cq_num], ctrl, &q[0], i);
        if (status != 0)
        {
            remove_queues(q, i);
            return status;
        }
    }
    printf("request_queues success\n");
    *queues = q;
    return status;
}



int main(int argc, char** argv)
{

    
    nvm_ctrl_t* ctrl;
    int status,ret;
    nvm_dma_t* aq_dma;
    struct disk disk;
    struct queue* queues = NULL;
    struct buffer buffer;
    int snvme_c_fd,snvme_d_fd;
    // Parse command line arguments
    int *buffer2;
    int ioq_num;
    int read_bytes;
    ioq_num = 1;
    read_bytes = 1024*64;
    void *buf__host = NULL;
    int *buf__host_int = NULL;
    const char *filename = "/home/qs/nvm_mount/test.data";
    int fd;
    struct queue_pair qp;
    struct file_info read_info;
    int snvme_helper_fd;
    struct nds_mapping mapping;
    uint64_t nvme_ofst;
    snvme_c_fd = open(snvme_control_path, O_RDWR | O_NONBLOCK);

    if (snvme_c_fd < 0)
    {

        fprintf(stderr, "Failed to open device file: %s\n", strerror(errno));
        exit(1);
    }

    // Get controller reference

    snvme_d_fd = open(snvme_path, O_RDWR | O_NONBLOCK);
    if (snvme_d_fd < 0)
    {
        fprintf(stderr, "Failed to open device file: %s\n", strerror(errno));
        exit(1);
    }

    status = nvm_ctrl_init(&ctrl, snvme_c_fd, snvme_d_fd);
    if (status != 0)
    {
        close(snvme_c_fd);
        close(snvme_d_fd);
        
        fprintf(stderr, "Failed to get controller reference: %s\n", strerror(status));
    }
    
    close(snvme_c_fd);
    close(snvme_d_fd);

    // ctrl->cq_num = 1;
    // ctrl->sq_num = 1;
    // ctrl->qs = 1024;
    // // Create queues
    // status = request_queues(ctrl, &ctrl->queues);
    // if (status != 0)
    // {
    //     goto out;
    // }
    // status =  ioctl_use_userioq(ctrl,1);
    // if (status != 0)
    // {
    //     goto out;
    // }
    // /*Prepare Buffer for read/write, need convert vaddt to io addr*/

    // status = create_buffer(&buffer, ctrl, 4096,0,-1);
    // if (status != 0)
    // {
    //     goto out;
    // }

    status =  ioctl_reg_nvme(ctrl,0);
    if (status != 0)
    {
        goto out;
    }

    // disk.page_size = ctrl->page_size;
    // disk.ns_id = 1;
    // sleep(5);

    // status =  init_userioq(ctrl,&disk);
    // if (status != 0)
    // {
    //     goto out;
    // }
    // printf("disk block size is %u, max data size is %u\n",disk.block_size,disk.max_data_size);
    // Host_file_system_int(nvme_dev_path,nvme_mount_path);
 
    
    // fd = open(filename, O_RDWR| O_CREAT | O_DIRECT , S_IRUSR | S_IWUSR);
    // ret = posix_memalign(&buf__host, 4096, read_bytes);
    // assert(ret==0);
    // assert(0 == ftruncate(fd, read_bytes*16));
    // buf__host_int = (int*)buf__host;
    // for (size_t i = 0; i < read_bytes / sizeof(int); i++)
    //     buf__host_int[i] = i;
    // snvme_helper_fd = open(snvme_helper_path, O_RDWR);
    // if (snvme_helper_fd < 0) {
    //     perror("Failed to open snvme_helper_fd");
    //     assert(0);
    // }
    // assert(read_bytes == pwrite(fd, buf__host_int, read_bytes,read_bytes));
    // fsync(fd);   

    // mapping.file_fd = fd;
    // mapping.offset = read_bytes;
    // mapping.len = read_bytes;
    // if (ioctl(snvme_helper_fd, SNVME_HELP_GET_NVME_OFFSET, &mapping) < 0) {
    //     perror("ioctl failed");
    //     assert(0);
    // }
    // nvme_ofst = mapping.address;
    // close(snvme_helper_fd);
    // close(fd);
    // printf("nvme_ofst is %lx,block size is %u\n",nvme_ofst,read_bytes);



    // qp.cq = &ctrl->queues[0];
    // qp.sq = &ctrl->queues[ctrl->cq_num];
    // qp.stop = false;
    // qp.num_cpls = 0;
    // printf("using cq is %u, sq is %u\n",qp.cq->queue.no,qp.sq->queue.no);
    // read_info.offset = nvme_ofst >> 9 ;
    // read_info.num_blocks = 4096 >> 9;
    // printf("offset is %lx, block num is %u\n",read_info.offset,read_info.num_blocks);
    // for(int  i = 0; i < 512; i++)
    //     status = read_and_dump(&disk,&qp,buffer.dma,&read_info);
    // //status = disk_read(&disk, &buffer, 1, read_bytes,ctrl);
    // printf("disk_read ret is %d\n",status);
    // buffer2 = (int *)buffer.buffer;
    // for (int i = 0; i < 256; i++) {  
    //     printf("%02X ", buffer2[i]); // 以十六进制形式打印  
    //     if ((i + 1) % 16 == 0) {  
    //         printf("\n"); // 每16个字节换行，方便查看  
    //     }  
    // }  

    // sleep(5);

out:
    // ret = Host_file_system_exit(nvme_dev_path);
    if(ret < 0)
        exit(-1);
    nvm_ctrl_free(ctrl);
    exit(status);
}
