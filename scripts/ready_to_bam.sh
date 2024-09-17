#!/bin/bash  
  
# 定义PCI地址  
PCI_ADDRESS="0000:63:00.0"  
  
# 检查参数  
if [ "$#" -ne 1 ]; then  
    echo "Usage: $0 <bind|unbind>"  
    exit 1  
fi  
  
# 定义函数来绑定或解绑NVMe驱动  
bind_or_unbind() {  
    local action=$1  
    local driver_dir="/sys/bus/pci/drivers/nvme"  
    local device_dir="/sys/bus/pci/devices/${PCI_ADDRESS}"  
    local bind_file="${driver_dir}/bind"  
    local unbind_file="${driver_dir}/unbind"  
  
    if [ "$action" == "unbind" ]; then  
        # 检查设备是否已经绑定到驱动  
        if [ -h "${device_dir}/driver" ]; then  
            echo "${PCI_ADDRESS}" > "${unbind_file}" || { echo "Failed to unbind NVMe device"; exit 1; }  
            echo "NVMe device at ${PCI_ADDRESS} unbound from driver."  
        else  
            echo "NVMe device at ${PCI_ADDRESS} is not bound to driver."  
        fi  
    elif [ "$action" == "bind" ]; then  
        # 检查设备是否已经绑定到驱动  
        if [ ! -h "${device_dir}/driver" ]; then  
            echo "${PCI_ADDRESS}" > "${bind_file}" || { echo "Failed to bind NVMe device"; exit 1; }  
            echo "NVMe device at ${PCI_ADDRESS} bound to driver."  
        else  
            echo "NVMe device at ${PCI_ADDRESS} is already bound to driver."  
        fi  
    else  
        echo "Invalid action: $action"  
        exit 1  
    fi  
}  
  
# 执行操作  
bind_or_unbind "$1"