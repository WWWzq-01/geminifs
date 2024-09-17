## Introduction
This directory contains the GPUfs source code and the interface between GPUfs and PyTorch.
In order to properly install gpufs on our server, make sure that the downloaded code branch is Master. Or download it directly: 

    $ git clone git@github.com:fanfanaaaa/gpufs.git

The implemented interfaces are: geminifs.save(), geminifs.load()

## Install
    $ ./install.sh 1   # 0 indicates uninstall

## Example

```
from api import Geminifs

model = MyNet()
model.to("cuda")
filepath = "your filepath to save checkpoints"
geminifs = Geminifs(filepath)
geminifs.save(model.state_dict())
geminifs.load()
