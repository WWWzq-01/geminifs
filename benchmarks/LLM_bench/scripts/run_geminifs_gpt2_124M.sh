#!/bin/bash 

make train_gpt2_geminifscu USE_CUDNN=1 -j80

out_dir="/home/hyf/nvme0n1_geminifs/log_gpt2_124M_geminifs"
done_file="$out_dir/DONE_00018865"

./train_gpt2_geminifscu \
    -i "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_train_*.bin" \
    -j "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_val_*.bin" \
    -e "/home/hyf/nvme0n1_geminifs/data/gpt2_124M_bf16.bin" \
    -o $out_dir \
    -v 250 -s 20000 -g 144 \
    -h 1 \
    -b 256 -t 1024 \
    -d 524288 \
    -r 0 \
    -z 1 \
    -c 0.1 \
    -l 0.0006 \
    -q 0.0 \
    -u 700 \
    -n 5000 \
    -y 0 \
    -n 2000 \