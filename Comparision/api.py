import os
import torch
import uuid
from typing import Callable, Optional, List
from collections import OrderedDict  
from Geminifs._C import GPUfs

class Geminifs(GPUfs):
    def __init__(self, filename: str, backend: str = 'GPUfs') -> None:
        self.backend = backend
        self.filename = filename
        super().__init__(filename, backend)
    
    
    def save(self, state_dict: OrderedDict) -> None:
        # print("调用Gemini.save成功, filename is ", filename)
        for key in state_dict:
            print(f"[PYTHON]: tensor_ptr:{hex(state_dict[key].data_ptr())}, write nbytes {state_dict[key].element_size() * state_dict[key].numel()}")
            super().gpufs_write(state_dict[key], key)
            
    
    # 调查torch.load是如何实现，怎么把tensor数据加载至设备，以及gread是读到设备还是CPU
    def load(self) -> None:    
        pass
        # for tensor in tensors:
        #     if tensor.storage().size() == 0:
        #         tensor.storage().resize_(tensor.numel())
        # key = str(hash(tuple(tensors)))
        # super().sync_readv(tensors, key)
        
        
    # def sync_read(self, tensor: torch.Tensor) -> None:
    #     if tensor.storage().size() == 0:
    #         tensor.storage().resize_(tensor.numel())
    #     super().sync_read(tensor, str(id(tensor)))

# geminifs = Geminifs()