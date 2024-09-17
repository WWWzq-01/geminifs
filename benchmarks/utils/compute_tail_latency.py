from tdigest import TDigest
import re

def parse_line(line):
    _, time_str = line.split(':')
    time_str = time_str.strip().split()[0]
    return float(time_str)

def process_file(input_file, thread):
    total_count = 0
    sum_latency = 0.0
    digest = TDigest()
    print(f"Filename: {input_file} ,Thread: {thread}")

    with open(input_file, 'r', encoding='utf-8') as infile:
        for line in infile:
            time_value = parse_line(line)

            total_count += 1
            sum_latency += time_value

            digest.update(time_value)

    avg_latency = sum_latency / total_count if total_count > 0 else 0
    p95 = digest.percentile(95)
    p99 = digest.percentile(99)
    p999 = digest.percentile(99.9)

    print(f"Total IOs: {total_count}")
    print(f"Average Latency: {avg_latency:.3f} us")
    print(f"95th Percentile Latency: {p95:.3f} us")
    print(f"99th Percentile Latency: {p99:.3f} us")
    print(f"99.9th Percentile Latency: {p999:.3f} us")
    print("#############################################################")


def replace_t_value(input_file, new_value):
    pattern = r'(t_)\d+'    
    new_file = re.sub(pattern, f't_{new_value}', input_file)
    
    return new_file
input_file = 'test_gds_cuFileRead_latency_threads_1.log'
process_file("./logs_BatchIO_p5800_0907/02_test_cuFileBatchIOSubmit_latency_bs_1.log", 1)
process_file("./logs_BatchIO_p5800_0907/02_test_cuFileBatchIOSubmit_latency_bs_4.log", 4)

process_file("./logs_BatchIO_p5800_0907/02_test_cuFileBatchIOSubmit_latency_bs_8.log", 8)
process_file("./logs_BatchIO_p5800_0907/02_test_cuFileBatchIOSubmit_latency_bs_16.log", 16)

process_file("./logs_BatchIO_p5800_0907/02_test_cuFileBatchIOSubmit_latency_bs_32.log", 32)
process_file("./logs_BatchIO_p5800_0907/02_test_cuFileBatchIOSubmit_latency_bs_64.log", 64)
process_file("./logs_BatchIO_p5800_0907/02_test_cuFileBatchIOSubmit_latency_bs_128.log", 128)
