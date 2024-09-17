#!/bin/bash  
  
# 定义IO大小和线程数数组  
IO_SIZE=(4 8 16 32 64 128 256)  
THREADS=(1 4 8 16 32 64)  
  
mkdir -p gdsio_logs  
  
logfile="./gdsio_logs/gdsio_result.txt" 
> ./gdsio_logs/gdsio_result.txt  

for threads in "${THREADS[@]}"  
do   
    # 遍历IO大小  
    for io_size in "${IO_SIZE[@]}"    
    do    
        # 创建或追加到日志文件，文件名包含IO大小和线程数  
         
  
        # 执行gdsio命令，注意移除了未定义的batch_size参数  
        /usr/local/cuda-12.3/gds/tools/gdsio -f ~/nvme0n1_geminifs/test_file.txt -d 0 -w "$threads" -s 32G -i "$io_size"K -x 0 -I 0 >> "$logfile"  
  
        # 可以在这里添加一些回显信息，以便跟踪进度  
        echo "Executed gdsio with IO size $io_size and threads $threads. Log saved to $logfile"  
    done    
done  
  
echo "All tests completed. Logs are saved in gdsio_logs directory."