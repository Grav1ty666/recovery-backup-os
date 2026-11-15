# Recovery & Backup OS

Windows 终端部署工具，用于在 x86-64 UEFI/GPT 设备上部署 Clonezilla 备份和恢复环境。

> **使用风险由使用者自行承担。** 分区、UEFI 启动项和恢复操作可能造成数据丢失或无法启动；部分功能尚未完成端到端验证。请先在可擦除虚拟机中测试，并准备独立备份。

## 功能

- **终端部署**：以管理员身份运行，扫描 Windows 系统盘及磁盘空间，选择启动分区和备份分区所在磁盘，并在执行前展示操作计划。
- **独立恢复环境**：创建恢复 ESP 与独立的 `BACKUP_OS` 备份分区，部署 Clonezilla 启动文件并注册 UEFI 启动项。
- **自动估算分区容量**：新建备份分区时，按 Windows 已用空间的 60% 计算，并向上取整到 10 GB 档位；实际压缩大小取决于数据，空间不足时备份可能失败。
- **系统备份**：使用 Clonezilla 备份 Windows 所在分区。首次成功备份设为基准 `partimag/BACKUP_OS`，后续备份使用带时间戳的目录名。
- **基准恢复**：`Recovery OS` 使用固定基准镜像；找不到基准时中止。恢复会覆盖 Windows 分区，完成后尝试自动重启。
- **启动菜单**：GRUB 尝试扫描并显示可识别的 UEFI 启动项，默认选择 Windows；也可选择 `Recovery OS` 或 `Backup OS`。多系统和固件兼容性尚待验证。
- **已有部署管理**：再次运行时检查备份分区，提供基准管理、日志导出和卸载选项。卸载会删除工具分区及其中的备份，相关功能尚待验证。
- **日志与错误码**：部署过程记录日志；错误码含义见 [ERROR-CODES.txt](ERROR-CODES.txt)。

本工具为开机菜单触发式备份和恢复，**不提供定时自动备份**。

## 下载安装程序

[下载 RecoveryBackupOS-Installer.exe](https://files.mali040929.dpdns.org/MyPrograms/RecoveryBackupOS/RecoveryBackupOS-Installer.exe)（Windows 安装程序）

## 下载

项目的 Clonezilla 运行文件使用 Git LFS 存储。请使用下面的方法下载完整文件：

1. 在 Windows 上安装 [Git](https://git-scm.com/install/windows) 和 [Git LFS](https://git-lfs.com/)。
2. 打开 Windows Terminal，依次执行：

   ```powershell
   git lfs install
   git clone https://github.com/Grav1ty666/recovery-backup-os.git
   cd recovery-backup-os
   git lfs pull
   ```

3. 确认下载完成，保留整个文件夹，再双击 `RecoveryConsole.exe`。

> 不建议直接使用 GitHub 的 **Code → Download ZIP**：源码压缩包可能只包含 LFS 指针，而不包含完整的 Clonezilla 运行文件。

## 使用

双击 `RecoveryConsole.exe`，按终端提示进行部署。运行需要 Windows PowerShell、.NET Framework 4.x 和管理员权限，不需要 Python。

部署会创建恢复 ESP 和独立的 `BACKUP_OS` 分区；备份镜像保存在 `partimag`，基准镜像名为 `BACKUP_OS`。程序只备份和还原 Windows 所在分区，不提供完整磁盘或 EFI 分区恢复。Secure Boot 和 BitLocker 不受支持。

GRUB 多系统扫描、启动顺序管理、卸载及故障恢复尚未完成端到端验证，不能保证适配所有固件和磁盘布局。更多功能边界见 [README.txt](README.txt)，错误代码见 [ERROR-CODES.txt](ERROR-CODES.txt)。

## 源码和构建

`source` 包含 Windows 部署程序、恢复脚本和 GRUB 扩展源码。`build.ps1` 构建 Windows 可执行文件；GRUB 的构建说明见 `source/build-grub-multios.sh`。项目包含 Clonezilla、Linux、GRUB 和其他第三方组件，其许可和源码分发要求分别适用。
