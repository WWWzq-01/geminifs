#!/bin/bash 

make train_gpt2_gpufscu USE_CUDNN=0 -j80

out_dir="/home/hyf/nvme0n1_geminifs/log_gpt2_124M_gpufs"
done_file="$out_dir/DONE_00018865"

sudo ./train_gpt2_gpufscu \
    -i "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_train_*.bin" \
    -j "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_val_*.bin" \
    -e "/home/hyf/nvme0n1_geminifs/data/gpt2_124M_bf16.bin" \
    -o "/home/hyf/nvme0n1_geminifs/log_gpt2_124M_gpufs" \
    -v 250 -s 20000 -g 144 \
    -h 1 \
    -b 64 -t 1024 \
    -d 524288 \
    -r 0 \
    -z 1 \
    -c 0.1 \
    -l 0.0006 \
    -q 0.0 \
    -u 700 \
    -n 5000 \
    -y 0 \
    -n 1  >> "gpufs_train_gpt2.log"