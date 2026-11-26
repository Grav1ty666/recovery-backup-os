# Recovery & Backup OS v1.1.0

Windows 终端部署工具，在 x86-64 UEFI/GPT 设备上部署 Clonezilla 备份和恢复环境。启动器优先调用 Windows Terminal，无法启动时回退到传统控制台。

**使用风险由使用者自行承担。** 分区、UEFI 启动项及恢复操作可能导致数据丢失或无法启动。部分功能尚未完成端到端验证，请先在可擦除的虚拟机中验证，并另行备份重要数据。

## 功能

- 支持新建隐藏备份分区、新建可见备份分区，或将镜像存入独立的已有可见数据分区目录。
- 选择已有分区时，Windows 系统分区不能存放自身的还原镜像；可选分区须符合程序的文件系统、加密和身份检查。备份目录及根目录警告文件不可随意删除。
- 部署前展示磁盘和压缩方案并要求确认。首次成功备份作为基准，后续备份按时间戳命名；恢复使用基准镜像。
- 支持基准镜像管理、导出日志和卸载恢复环境。已有分区模式下保留承载数据的分区，删除工具拥有的备份目录和恢复启动分区；专用分区模式移除对应的备份分区和恢复启动分区。
- 从 Windows 启动菜单选择 Backup OS 或 Recovery OS。此工具不提供整盘或原有 EFI 分区恢复，不支持 Secure Boot 和 BitLocker。

## 安装

从 [v1.1.0 Release](https://github.com/Grav1ty666/recovery-backup-os/releases/tag/v1.1.0) 下载 `RecoveryBackupOS-Setup-v1.1.0.exe`。安装包已包含 Clonezilla 运行资源，启动部署工具需要管理员权限。安装器的程序卸载只删除应用文件；恢复环境卸载需在终端管理界面中进行。

## 构建

仓库的 Clonezilla 资源通过 Git LFS 存储。克隆后运行 `git lfs pull`，在 Windows 下执行 `build.ps1`，再使用 Inno Setup 编译 `recovery-setup.iss`。直接下载 GitHub 源码 ZIP 可能只获得 LFS 指针。错误代码说明见 [ERROR-CODES.txt](ERROR-CODES.txt)。
