project(geminifs  
        DESCRIPTION "Geminifs interface for save and load checkpoints."  
        LANGUAGES CXX CUDA)  
# Define GPUFS and CUDA directories
set(GPUFS_DIR ${GPUFS_DIR}/home/hyf/Ganymede/Comparision/gpufs)
set(CUDA_DIR ${CUDA_DIR}/usr/local/cuda)
set(LIBCUDA ${LIBCUDA}/usr/local/cuda/lib64)
set(CUDAINC ${CUDAINC}/usr/local/cuda/include)
set(GPUFS_LIBRARY "${GPUFS_DIR}/lib/libgpufs.a")  

include_directories(${PROJECT_SOURCE_DIR}
                    ${GPUFS_DIR}/include
                    ${CUDAINC}
                    )

link_directories(${GPUFS_DIR}/lib/ 
                 ${LIBCUDA})

# Set compiler flags
set(CMAKE_CXX_FLAGS "-O2")
set(CMAKE_CUDA_FLAGS "-O2 --std=c++11 --generate-code code=sm_80,arch=compute_80 -maxrregcount 32")


set(SOURCES
    api.cpp
    api_gpu.cu
    space_mgr.cpp
)
aux_source_directory(${GPUFS_DIR}/libgpufs GPUFS_SRC_FILES)

# Create static library
add_library(${PROJECT_NAME} STATIC ${SOURCES})

# 设置CUDA编译器标志  
set_target_properties(${PROJECT_NAME} PROPERTIES  
    CUDA_COMPILE_OPTIONS "-O2 --std=c++11 --generate-code=arch=compute_80,code=sm_80 -maxrregcount 32"  
)  
target_link_libraries(${PROJECT_NAME} PRIVATE ${GPUFS_LIBRARY} cudart_static)  


