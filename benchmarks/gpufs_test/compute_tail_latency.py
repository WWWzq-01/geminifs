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

input_file = 'test_gpufs_read_latency_4M_b_1_t_1.log'
# process_file(input_file, 1)
threadList = [1, 16, 32, 64, 128, 256, 512, 1024, 2048]
for thread in threadList:
    filename = replace_t_value(input_file, thread) 
    process_file(filename, thread)
