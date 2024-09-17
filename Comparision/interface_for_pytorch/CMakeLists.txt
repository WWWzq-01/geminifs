cmake_minimum_required(VERSION 3.16)
project(
        Geminifs
        DESCRIPTION "Geminifs interface for save and load checkpoints."
        LANGUAGES CXX CUDA
)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)



add_subdirectory(csrc)

