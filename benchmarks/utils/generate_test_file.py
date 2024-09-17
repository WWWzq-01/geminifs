import os  
  
def generate_test_file(file_path, size_in_gb):  
    # 将GB转换为字节  
    size_in_bytes = int(size_in_gb * (1 << 30))  
    # 打开文件  
    with open(file_path, 'wb') as f:  
        # 每次写入的块大小（例如1MB）  
        block_size = 1 << 20  
        # 写入块的次数  
        blocks = size_in_bytes // block_size  
        # 剩余的字节数  
        remaining_bytes = size_in_bytes % block_size  
        # 写入完整的块  
        data = os.urandom(block_size)  
        for _ in range(blocks):  
            f.write(data)  
        # 写入剩余的字节  
        if remaining_bytes > 0:  
            f.write(os.urandom(remaining_bytes))  
  
if __name__ == "__main__":  
    # 提示用户输入文件大小（GB）  
    size_in_gb = input("请输入要生成的文件大小（GB）: ")  
    try:  
        # 尝试将输入转换为整数  
        size_in_gb = int(size_in_gb)  
        if size_in_gb <= 0:  
            print("文件大小必须大于0 GB。")  
        else:  
            # 生成文件  
            generate_test_file("../test_file.txt", size_in_gb)  
            print("Test file generated successfully.")  
    except ValueError:  
        # 如果输入无法转换为整数，打印错误消息  
        print("请输入一个有效的整数作为文件大小（GB）。")