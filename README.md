# Recovery & Backup OS

Windows 终端部署工具，用于在 x86-64 UEFI/GPT 设备上部署 Clonezilla 备份和恢复环境。

> **实验版本。** 分区、UEFI 启动项和恢复操作可能造成数据丢失或无法启动；新功能尚未完成端到端验证。请先在可擦除虚拟机中测试，并准备独立备份。

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

GRUB 多系统扫描、启动顺序管理、卸载及故障恢复属于实验功能，不能保证适配所有固件和磁盘布局。更多功能边界见 [README.txt](README.txt)，错误代码见 [ERROR-CODES.txt](ERROR-CODES.txt)。

## 源码和构建

`source` 包含 Windows 部署程序、恢复脚本和 GRUB 扩展源码。`build-experimental.ps1` 构建 Windows 可执行文件；GRUB 的构建说明见 `source/build-grub-multios.sh`。项目包含 Clonezilla、Linux、GRUB 和其他第三方组件，其许可和源码分发要求分别适用。
