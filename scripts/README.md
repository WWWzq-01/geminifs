# scripts 目录说明

- `create_nv.symvers.sh`: 收集 NVIDIA 驱动的 `nvidia_p2p_*` 符号，必要时临时编译驱动源码，生成 `nv.symvers` 供自定义内核模块链接使用。
- `Module.symvers`: 现成的符号版本映射文件，供项目内核模块编译解析依赖符号。
- `nv.symvers`: 由 `create_nv.symvers.sh` 生成的 NVIDIA 相关符号版本清单。
- `nvme_module_change.sh`: 切换系统自带 NVMe 模块与自定义 SNVMe 模块。`share`/`reload` 装载 `snvme(-core).ko`，`origin` 切回系统 NVMe，`reloadp` 只处理 `snvme`。
- `nvme_unreg.c`: 通过 ioctl 对 NVMe 设备执行注册/注销的示例源码（使用 `_IO('N', 0/1)`），可用 `gcc -o nvme_unreg nvme_unreg.c` 编译。
- `nvme_unreg.py`: Python 版 ioctl 示例，需将占位 ioctl 常量替换为实际值后使用。
- `nvme_unreg`: 已编译的二进制工具，用于对指定设备执行注册/注销 ioctl。
- `ready_to_bam.sh`: 将 PCI 地址 `0000:63:00.0` 的设备绑定或解绑到内核 `nvme` 驱动（参数 `bind` 或 `unbind`）。
- `ready_to_run.sh`: 环境准备脚本；检测 `/dev/nvme0n1` 与 `/dev/snvme`，必要时卸载挂载分区，调用 `nvme_module_change.sh share/reload` 切换驱动，若已有 SNVMe 先注销再重载。
- `recovery_to_origin.sh`: 恢复流程，先执行 `ready_to_run.sh`，随后调用 `nvme_module_change.sh origin` 切回系统 NVMe 驱动。

## Typical runtime order 
- Start in `scripts/` with root: `sudo ./ready_to_run.sh` (prepares env, switches to `snvme(-core).ko` as needed).
- (Optional) PCI bind/unbind the target drive: `sudo ./ready_to_bam.sh unbind` or `bind` (default PCI `0000:63:00.0`).
- Run your tests or tools. For manual controller register/unregister: `sudo ./nvme_unreg /dev/snvm_control 0|1` (0/1 per ioctl definition).
- Restore system NVMe driver: `sudo ./recovery_to_origin.sh` (runs `ready_to_run.sh` then `nvme_module_change.sh origin`).
