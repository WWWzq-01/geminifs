#!/bin/bash -x

THREADS=(1 16 32 64 128) 
IO_SIZE=(4 8 16 32 64 128 256) # KB
BATCH_SIZE=(1 32 64 128 256)

mkdir logs
for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./logs/03_test_cuFileRead_bandwith_io_${io_size}.log"  
    rm -rf "$logfile"
 
    # ./02_test_cuFileBatchIOSubmit_latency 80000 ~/nvme0n1_geminifs/test_file.txt 0 "$batch_size" 0 >> "$logfile"
    ./03_test_cuFileRead_bandwith 0 ~/nvme0n1_geminifs/test_file.txt 0 100000 "$io_size" >> "$logfile"
    echo "Run 03_test_cuFileRead_bandwith success: io_size=${io_size}"  
done  
mkdir with_logs
for io_size in "${IO_SIZE[@]}"  
do  
    logfile="./with_logs/03_test_cuFileRead_bandwith_io_${io_size}.log"  
    rm -rf "$logfile"
 
    # ./02_test_cuFileBatchIOSubmit_latency 80000 ~/nvme0n1_geminifs/test_file.txt 0 "$batch_size" 0 >> "$logfile"
    ./03_test_cuFileRead_bandwith 0 ~/nvme0n1_geminifs/test_file.txt 1 100000 "$io_size" >> "$logfile"
    echo "Run 03_test_cuFileRead_bandwith success: io_size=${io_size}"  
done  