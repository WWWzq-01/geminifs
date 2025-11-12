# GeminiFS 中 CPU/GPU 共享 NVMe SSD 的实现

## 整体思路
- GeminiFS 在 Linux 内核 NVMe PCI 驱动之上做增量修改（`kernel_module/nvme/host`），实现 SNVMe 扩展：既保留原生 blk-mq 路径供 CPU 使用，又允许用户态注册 GPU/CPU 自管的 NVMe IO 队列（`kernel_module/README.md`，`kernel_module/nvme/host/pci.c:3189-3231`）。
- 因为控制器初始化和 admin queue 仍由内核驱动负责，CPU 访问 `/dev/nvme*` 的体验保持不变；GPU 只是在注册完成后获得额外的 SQ/CQ 缓冲区和 doorbell 权限。

## 共享队列注册流程
1. 用户态库先通过 `/dev/snvme*` 的 `NVM_SET_IOQ_NUM` 指定要接管的队列数量以及队列所在内存类型（主机内存或 GPU 显存），驱动将其写入 `struct ctrl` 的 `ioq_num/on_host` 字段（`src/linux/ioctl.h:8-34`，`src/linux/device.cpp:95-118`，`kernel_module/nvme/host/ctrl.h:16-33`）。
2. 随后调用 `NVM_MAP_HOST_MEMORY` 或 `NVM_MAP_DEVICE_QUEUE_MEMORY`：
   - 主机内存路径：`get_user_pages` pin 住用户页，`dma_map_page` 生成 NVMe 可用的 DMA 地址（`kernel_module/nvme/host/map.c:180-238`，`kernel_module/nvme/host/pci.c:3658-3695`）。
   - GPU 内存路径：借助 NVIDIA P2P API（`nvfs_nvidia_p2p_get_pages` / `dma_map_pages`）把 CUDA 显存映射为控制器可访问的物理地址，并保存到 `struct map`（`kernel_module/nvme/host/map.c:375-520`，`kernel_module/nvme/host/pci.c:3700-3757`）。
3. 每次映射都会记录队列索引与类型，并累计 `ctrl->ioq_map_num/cq_num`；只有当“映射数量 == 期望队列数”且用户调用 `NVM_SET_SHARE_REG` 置位后，驱动才允许在 probe 中启用用户自管队列（`kernel_module/nvme/host/pci.c:3838-3871`）。

## 驱动端如何实现 CPU/GPU 共享
- `nvme_probe` 检查上述条件，如果满足就把 `dev->use_user_allocated=1`、记录用户队列位于主机或 GPU，后续创建队列时即可混合使用（`kernel_module/nvme/host/pci.c:3189-3231`）。
- `nvme_setup_io_queues` 在向控制器申请队列数量时把“内核需要的 blk-mq 队列”与“用户自管的 CQ 数量”相加，成功后记下 `nr_user_use_cq`/`user_start_qid`（`kernel_module/nvme/host/pci.c:2446-2594`）。
- 标准 blk-mq 队列通过 `nvme_create_io_queues` 建好，随后 `nvme_create_io_queues_mix` 调用 `nvme_create_user_queue`，利用前面保存的 DMA 缓冲区地址，通过 admin queue 的 `Create SQ/CQ` 指令把控制器的 PRP 指向主机内存或 GPU 显存（`kernel_module/nvme/host/pci.c:1943-1972`，`kernel_module/nvme/host/pci.c:1738-1785`，`kernel_module/nvme/host/pci.c:1241-1285`）。
- 因为 admin queue 仍在 CPU，驱动可以统一处理重置、超时、错误，而 GPU/CPU 用户态只需按照 NVMe 协议向自己的 SQ 写命令。

## Doorbell 与用户态操作
- `/dev/snvme*` 提供 `mmap` 能力把 NVMe BAR0（含 doorbell）映射到用户态，可由 CPU 直接写入或进一步注册给 GPU（`kernel_module/nvme/host/pci.c:3921-3947`，`src/linux/device.cpp:288-365`）。
- 用户空间库 `init_userioq` 在拿到 `start_cq_idx`、队列深度等信息后，用 `nvm_queue_clear` 将本地元数据指向相同的 SQ/CQ 缓冲区，实现与内核共享同一份队列（`src/linux/device.cpp:153-209`，`src/queue.cpp:1-44`）。
- 若需要 GPU 直接定位文件数据，`snvme_helper` 通过 ext4 extent cache 返回物理 LBA，供 GPU 以零拷贝方式读取，但 CPU 路径依旧保持（`kernel_module/nvme/host/snvme_help.c:1-94`）。

## 建议
1. 通过 `benchmarks/test_prp` 等示例验证在 GPU 注册队列的同时，CPU 仍可正常访问 `/dev/nvme*`。
2. 在设置自定义队列数量前查询控制器 `CAP.MQES`，避免 `nvme_set_queue_count` 申请超出上限；必要时可改进 `nvme_setup_io_queues` 的降级策略。
