#include <stdio.h>  
#include <stdlib.h>  
#include <fcntl.h>  
#include <sys/ioctl.h>  
#include <unistd.h>  
//  gcc -o nvme_unreg nvme_unreg.c

// 假设这些是你要使用的 ioctl 命令编号，实际编号需要根据你的需求来定  
#define SNVM_REGISTER_DRIVER	_IO('N', 0x0)
#define SNVM_UNREGISTER_DRIVER	_IO('N', 0x1)
  
int main(int argc, char *argv[]) {  
    if (argc != 3) {  
        fprintf(stderr, "Usage: %s <device> <command>\n", argv[0]);  
        fprintf(stderr, "command: 1 for ioctl command 1, 0 for ioctl command 0\n");  
        return 1;  
    }  
  
    const char *device = argv[1];  
    int command = atoi(argv[2]);  
  
    if (command != 0 && command != 1) {  
        fprintf(stderr, "Invalid command. Command should be either 0 or 1.\n");  
        return 1;  
    }  
  
    int fd = open(device, O_RDWR);  
    if (fd == -1) {  
        perror("Failed to open device");  
        return 1;  
    }  
  
    int ioctl_command = (command == 1) ? SNVM_REGISTER_DRIVER : SNVM_UNREGISTER_DRIVER;  
    int result = ioctl(fd, ioctl_command);  
    if (result == -1) {  
        perror("Failed to execute ioctl command");  
        close(fd);  
        return 1;  
    }  
  
    close(fd);  
    return 0;  
}