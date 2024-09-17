#!/bin/bash -x
NUM_REQUESTS=(1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576 2097152 4194304 8388608 16777216 33554432)
logfile="bam_num_reqs_results.log"  

for num_reqs in "${NUM_REQUESTS[@]}"  
do
    sudo /home/hyf/Ganymede/Comparision/bam/build/bin/nvm-block-bench  --reqs="$num_reqs" --threads=1  --blk_size=4096 --ssd=1 --pages=262144 --access_type=0 --queue_depth=1024  --num_blks=2097152 --gpu=0 --n_ctrls=1 --num_queues=128 --random=false --page_size=4096 >> "$logfile" 
    echo "Run test success, num_reqs=$num_reqs" >> "$logfile"  

done
