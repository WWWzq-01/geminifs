#!/bin/bash -x  
BLOCK_SIZE=(4096 8192 16384 32768 65536 131072 262144)  
logfile="bam_block_size_results.log"  
#!/bin/bash -x  
# logfile="bam_block_size_results.log"  
  
for block_size in "${BLOCK_SIZE[@]}"  # 使用双引号来确保数组元素被正确遍历  
do  
    sudo /home/hyf/Ganymede/Comparision/bam/build/bin/nvm-block-bench  --threads=1  --blk_size="$block_size" --ssd=1 --reqs=1 --access_type=0 --queue_depth=1024 --gpu=0 --n_ctrls=1 --random=false --page_size=4096 >> "$logfile" 
  
    echo "Run test success, block_size=$block_size" >> "$logfile"  
done