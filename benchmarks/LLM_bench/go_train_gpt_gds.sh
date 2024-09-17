#!/bin/bash
 ./scripts/run_gpt2_124M.sh > train_gpt2_native.log 
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