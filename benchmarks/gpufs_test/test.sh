#!/bin/bash -x
# make clean; make
# BLOCKS=(1)  
# THREADS=(1 4 8 16 32 64 128 256 512 1024)  
# mkdir 0907
# for blocks in "${BLOCKS[@]}"  
# do  
#     for threads in "${THREADS[@]}"  
#     do  
#         logfile="./0907/test_gpufs_read_latency_4M_b_${blocks}_t_${threads}.log"  
        
#         rm "$logfile"
#         if [ "$threads" -eq 256 ]; then
#             ./01_test_read_latency 10 "$blocks" "$threads" ~/nvme0n1_geminifs/test_file.txt >> "$logfile"
#         elif [ "$threads" -eq 512 ] ; then
#            ./01_test_read_latency 20 "$blocks" "$threads" ~/nvme0n1_geminifs/test_file.txt >> "$logfile"
#         elif [ "$threads" -eq 1024 ]; then
#             ./01_test_read_latency 42 "$blocks" "$threads" ~/nvme0n1_geminifs/test_file.txt >> "$logfile"
#         else
#             ./01_test_read_latency 1 "$blocks" "$threads" ~/nvme0n1_geminifs/test_file.txt >> "$logfile"
#         fi
#         echo "Run test_gpufs_read_latency success: blocks=${blocks}, threads=${threads}"  
#     done  
# done

#################实验一#########################################
# rm -rf logs
# mkdir logs
IO_SIZE=(4 8 16 32 64 128 256)  
# for io_size in "${IO_SIZE[@]}"  
# do  
#     logfile="./logs/02_test_read_bandwidth_thread1_io_${io_size}.log"  
    
#     ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 1 "$io_size" >> "$logfile"
# # ./02_test_read_bandwidth ~/nvme0n1_geminifs/text_file.txt 1 1 16 4
#     echo "Run 02_test_read_bandwidth success, threads=1,  IO_SIZE=${io_size}"  
# done  


# for io_size in "${IO_SIZE[@]}"  
# do  
#     logfile="./logs/02_test_read_bandwidth_thread4_io_${io_size}.log"  
    
#     ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 4 "$io_size" >> "$logfile"

#     echo "Run 02_test_read_bandwidth success, threads=4,  IO_SIZE=${io_size}"  
# done  
# for io_size in "${IO_SIZE[@]}"  
# do  
#     logfile="./logs/02_test_read_bandwidth_thread8_io_${io_size}.log"  
    
#     ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 8 "$io_size" >> "$logfile"

#     echo "Run 02_test_read_bandwidth success, threads=8,  IO_SIZE=${io_size}"  
# done  

# for io_size in "${IO_SIZE[@]}"  
# do  
#     logfile="./logs/02_test_read_bandwidth_thread16_io_${io_size}.log"  
    
#     ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 16 "$io_size" >> "$logfile"

#     echo "Run 02_test_read_bandwidth success, threads=16,  IO_SIZE=${io_size}"  
# done  
mkdir logs
for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./logs/02_test_read_bandwidth_thread32_io_${io_size}.log"  
    
    ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 32 "$io_size" >> "$logfile"

    echo "Run 02_test_read_bandwidth success, threads=32,  IO_SIZE=${io_size}"  
done  

for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./logs/02_test_read_bandwidth_thread64_io_${io_size}.log"  
    
    ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 64 "$io_size" >> "$logfile"

    echo "Run 02_test_read_bandwidth success, threads=64,  IO_SIZE=${io_size}"  
done  


for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./logs/02_test_read_bandwidth_thread128_io_${io_size}.log"  
    
    ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 128 "$io_size" >> "$logfile"

    echo "Run 02_test_read_bandwidth success, threads=128,  IO_SIZE=${io_size}"  
done  

for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./logs/02_test_read_bandwidth_thread256_io_${io_size}.log"  
    
    ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 256 "$io_size" >> "$logfile"

    echo "Run 02_test_read_bandwidth success, threads=256,  IO_SIZE=${io_size}"  
done  


for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./logs/02_test_read_bandwidth_thread512_io_${io_size}.log"  
    
    ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 512 "$io_size" >> "$logfile"

    echo "Run 02_test_read_bandwidth success, threads=512,  IO_SIZE=${io_size}"  
done  

for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./logs/02_test_read_bandwidth_thread1024_io_${io_size}.log"  
    
    ./02_test_read_bandwidth  ~/nvme0n1_geminifs/test_file.txt 1 1 1024 "$io_size" >> "$logfile"

    echo "Run 02_test_read_bandwidth success, threads=1024,  IO_SIZE=${io_size}"  
done  