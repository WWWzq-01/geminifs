#!/bin/bash -x
# sudo mount /dev/nvme0n1 /home/hyf/nvme0n1_geminifs
make train_gpt2cu USE_CUDNN=0 -j8
# sudo cp -r /home/hyf/Ganymede/benchmarks/LLM_Test/llm.c/dev/data /home/hyf/nvme0n1_geminifs
# sudo cp /home/hyf/Ganymede/benchmarks/LLM_Test/llm.c/gpt2_124M_bf16.bin  /home/hyf/nvme0n1_geminifs/data/

out_dir="/home/hyf/nvme0n1_geminifs/log_gpt2_124M_native"
done_file="$out_dir/DONE_00018865"

sudo ./train_gpt2cu \
    -i "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_train_*.bin" \
    -j "/home/hyf/nvme0n1_geminifs/data/fineweb10B/fineweb_val_*.bin" \
    -e "/home/hyf/nvme0n1_geminifs/data/gpt2_124M_bf16.bin" \
    -o $out_dir \
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
    -n 1  >> "native_train_gpt2.log"
# make train_gpt2cu USE_CUDNN=0 -j80
# ./train_gpt2cu \
#     -i "./dev/data/fineweb10B/fineweb_train_*.bin" \
#     -j "./dev/data/fineweb10B/fineweb_val_*.bin" \
#     -e "./gpt2_124M_bf16.bin" \
#     -o output.log \
#     -v 250 -s 20000 -g 144 \
#     -h 1 \
#     -b 64 -t 1024 \
#     -d 524288 \
#     -r 0 \
#     -z 1 \
#     -c 0.1 \
#     -l 0.0006 \
#     -q 0.0 \
#     -u 700 \
#     -n 5000 \
#     -y 0 \
#     -n 2000 >> check_offload_and_load_time_and_size.log 