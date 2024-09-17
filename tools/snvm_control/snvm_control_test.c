#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>  
#include <sys/ioctl.h> 
#include "snvm_control_test.h"
// #define file_path "/home/qs/fio_test/fio_test"
#define snvme_control_path "/dev/snvm_control"
#define snvme_path "/dev/snvme0"
int main(int argc, char *argv[]) 
{
    int  fd_control;  
    // open file

    fd_control = open(snvme_control_path, O_RDWR);  

    if (fd_control < 0) {  

        perror("Failed to open fd_dev");  
        return -1;  
    } 





    
    if (ioctl(fd_control, SNVM_REGISTER_DRIVER, NULL) < 0) {  
        perror("ioctl failed");  
        close(fd_control);  
        return -1;  
    }
    else
    {
        printf("SNVM_REGISTER_DRIVER success");
    }

    if (ioctl(fd_control, SNVM_UNREGISTER_DRIVER, NULL) < 0) {  
        perror("ioctl failed");  
        close(fd_control);  
        return -1;  
    }
    else
    {
        printf("SNVM_UNREGISTER_DRIVER success");
    }
    // constrst nds mapping


    close(fd_control);  
    return 0;
}
