#!/bin/bash 
  
if [ "$#" -ne 1 ]; then  
    echo "Usage: $0 <option>"  
    echo "Options:"  
    echo "  native"  
    echo "  gds"  
    echo "  gpufs"  
    echo "  geminifs"  
    exit 1  
fi 

option=$1  
  
case $option in  
    native)  
        ./scripts/run_native_gpt2_124M.sh
        ;;  
    gds)  
        ./scripts/run_gds_gpt2_124M.sh 
        ;;  
    gpufs)  
        ./scripts/run_gpufs_gpt2_124M.sh
        ;;  
    geminifs)  
        ./scripts/run_geminifs_gpt2_124M.sh
        ;;  
    *)  
        echo "Invalid option: $option"  
        echo "Use one of the following options:"  
        echo "  native"  
        echo "  gds"  
        echo "  gpufs" 
        echo "  geminifs" 
        exit 1  
        ;;  
esac  







# ./train_gpt2_gpufscu \
#                 -i "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_train_*.bin" \
#                 -j "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_val_*.bin" \
#                 -e "/home/hyf/nvme0n1_geminifs/data/gpt2_124M_bf16.bin" \
#                 -o $out_dir \
#                 -v 250 -s 20000 -g 144 \
#                 -h 1 \
#                 -b 4 \
#                 -t 1024 \
#                 -d 524288 \
#                 -r 0 \
#                 -z 1 \
#                 -c 0.1 \
#                 -l 0.0006 \
#                 -q 0.0 \
#                 -u 700 \
#                 -n 5000 \
#                 -y 0 \
#                 -n 2000 \
          
#  ./scripts/run_gpt2_124M.sh 
# ./train_gpt2_gdscu \
#     -i "dev/data/fineweb10B/fineweb_train_*.bin" \
#     -j "dev/data/fineweb10B/fineweb_val_*.bin" \
#     -o log124M \
#     -e "d12" \
#     -b 64 -t 1024 \
#     -d 524288 \
#     -r 1 \
#     -z 1 \
#     -c 0.1 \
#     -l 0.0006 \
#     -q 0.0 \
#     -u 700 \
#     -n 5000 \
#     -v 250 -s 20000 \
    

# nohup ./train_gpt2_gdscu \
#     -i "dev/data/fineweb10B/fineweb_train_*.bin" \
#     -j "dev/data/fineweb10B/fineweb_val_*.bin" \
#     -o log124M_gpt2_gds \
#     -e "d12" \
#     -b 64 -t 1024 \
#     -d 524288 \
#     -r 1 \
#     -z 1 \
#     -c 0.1 \
#     -l 0.0006 \
#     -q 0.0 \
#     -u 700 \
#     -n 5000 \
#     -v 250 -s 20000 \
#     -h 1 > train_gpt2_gdscu.log 2>&1 &