import os,re
def calculate_average_bandwidth(file_path):
    bandwidths = []

    # 打开文件并逐行读取
    with open(file_path, 'r') as file:
        for line in file:
            # 假设每一行的格式是："Bandwidth is YMB/s"
            match = re.search(r'Bandwidth: (\d+\.\d+) MB/s', line)  
            if match:
                bandwidth_str = match.group(1)  # 获取数字部分
                bandwidth = float(bandwidth_str)  # 转换为浮点数
                # print(f"提取的带宽值是: {bandwidth}")
                bandwidths.append(bandwidth)
            else:
                
                print("无法提取带宽值")
         

    # 计算带宽均值
    if bandwidths:
        average_bandwidth = sum(bandwidths) / len(bandwidths)
        return average_bandwidth
    else:
        return None

def process_logs_directory(directory_path):
    # 遍历logs目录下的所有文件
    for filename in os.listdir(directory_path):
        file_path = os.path.join(directory_path, filename)
        if os.path.isfile(file_path):  # 确保是文件
            average_bandwidth = calculate_average_bandwidth(file_path)
            if average_bandwidth is not None:
                print(f"文件 {filename} 的带宽均值为: {average_bandwidth:.3f} MB/s")
            else:
                print(f"文件 {filename} 中没有有效的带宽数据")

# 使用示例
logs_directory = 'with_logs'  # logs 目录路径
process_logs_directory(logs_directory)
