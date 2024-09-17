#!/bin/env python
import torch
# import Geminifs
from api import Geminifs

import torch.nn as nn
import torch.optim as optim
from torch.optim import lr_scheduler
import numpy as np
import torchvision
from torchvision import datasets, models, transforms
import matplotlib.pyplot as plt
import time
import os
import copy


class MyNet(nn.Module):
    def __init__(self):
        super(MyNet, self).__init__()
        self.conv1 = nn.Conv2d(3, 6, 5)
        self.pool = nn.MaxPool2d(2, 2)
        self.conv2 = nn.Conv2d(6, 16, 5)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)
 
    def forward(self, x):
        x = self.pool(F.relu(self.conv1(x)))
        x = self.pool(F.relu(self.conv2(x)))
        x = x.view(-1, 16 * 5 * 5)
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        x = self.fc3(x)
        return x
 

model = MyNet()
model.to("cuda")
geminifs = Geminifs("/home/hyf/Ganymede/Comparision/Geminnifs_save.txt")
geminifs.save(model.state_dict())
# # optimizer = optim.SGD(model.parameters(), lr=0.001, momentum=0.9)
# # print("Optimizer's state_dict:")
# # """
# # {'state': {}, 'param_groups': [{'lr': 0.001, 'momentum': 0.9, 'dampening': 0, 'weight_decay': 0, 'nesterov': False, 'maximize': False, 'foreach': None, 'differentiable': False, 'fused': None, 'params': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]}]}
# # """
# # for var_name in optimizer.state_dict():
# #     print(var_name, "\t", type(optimizer.state_dict()[var_name]))
 
# print("Model's state_dict type :", type(model.state_dict()))
# # for param_tensor in model.state_dict():
# #     # param_tensor -> str, model.state_dict()[param_tensor] -> torch.Tensor
# #     # print(param_tensor, "\t", model.state_dict()[param_tensor])
# #     break
# geminifs.save(model.state_dict(), "./Geminifs_MyNet.pt")
# # 将模型参数保存到系统文件
# torch.save(model.state_dict(), "./myNet.pt")


# # torch.load('tensors.pt') 
# # torch.load('tensors.pt', map_location=torch.device('cpu'))
# # torch.load('tensors.pt', map_location=lambda storage, loc: storage) 
# # torch.load('tensors.pt', map_location=lambda storage, loc: storage.cuda(1))

# """
# torch.save({
#             'epoch': epoch,
#             'model_state_dict': model.state_dict(),
#             'optimizer_state_dict': optimizer.state_dict(),
#             'loss': loss,
#             ...
#             }, PATH)
# """

 
# print("############################################")
# # 将模型参数保存到GPUfs
# # parameters类型相比传统tensor多了梯度信息
# # for parameters in model.parameters():
# #     geminifs.save(parameters)
# #     print(parameters)
# #     break



 
