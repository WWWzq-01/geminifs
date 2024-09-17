import os  
import sys  
import fcntl  
  
def nvme_ioctl(device, command):  
    # Open the device file  
    try:  
        fd = os.open(device, os.O_RDWR)  
    except OSError as e:  
        print(f"Failed to open device {device}: {e}")  
        return -1  
  
    try:  
        # Execute the ioctl command  
        result = fcntl.ioctl(fd, command)  
    except OSError as e:  
        print(f"Failed to execute ioctl command {command}: {e}")  
        result = -1  
    finally:  
        os.close(fd)  
  
    return result  
  
if __name__ == "__main__":  
    if len(sys.argv) != 3:  
        print(f"Usage: {sys.argv[0]} <device> <command>")  
        print("command: 1 for ioctl command 1, 0 for ioctl command 0")  
        sys.exit(1)  
  
    device = sys.argv[1]  
    command = int(sys.argv[2])  
  
    if command not in (0, 1):  
        print("Invalid command. Command should be either 0 or 1.")  
        sys.exit(1)  
  
    # Define the actual ioctl numbers (these are placeholders, replace with real ioctl numbers)  
    IOCTL_COMMAND_0 = 0x0  # Replace with the actual ioctl number for command 0  
    IOCTL_COMMAND_1 = 0x1  # Replace with the actual ioctl number for command 1  
  
    ioctl_command = IOCTL_COMMAND_1 if command == 1 else IOCTL_COMMAND_0  
  
    result = nvme_ioctl(device, ioctl_command)  
    if result == 0:  
        print(f"ioctl command {command} executed successfully.")  
    else:  
        print(f"Failed to execute ioctl command {command}.")