#!/bin/bash -x
make train_gpt2_gdscu USE_CUDNN=1 -j80
make train_gpt2cu USE_CUDNN=1 -j80
make train_gpt2_gpufscu USE_CUDNN=1 -j80
