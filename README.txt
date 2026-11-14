Clonezilla Recovery — Windows 终端部署项目（实验版）

使用前请完整阅读。部署会修改磁盘分区与 UEFI；恢复会覆盖 Windows 分区。请先在可擦除的虚拟机中使用，并准备独立备份。

一、使用
1. 将整个项目文件夹复制到目标 Windows 电脑。不要只复制 exe；assets 和 resources 是必需的。
2. 双击 RecoveryConsole.exe，同意管理员授权。优先使用 Windows Terminal；未安装 Windows Terminal 时回退到系统控制台。
3. 根据终端提示查看磁盘并选择存储位置。程序展示计划后按一次 Enter 执行分区与部署操作。
4. 在固件启动菜单中选择 Recover and Backup OS。恢复启动项会被设置为固件第一启动项，其余原有启动项保持相对顺序。
5. GRUB 启动时扫描 UEFI BootOrder，以固件提供的名称显示 Windows 和其他符合条件的 EFI 启动项。Windows 优先排列，若找到 Windows，两秒内无操作启动首个 Windows；否则关闭自动启动。使用方向键和 Enter 选择。

二、备份和恢复
- 新建镜像分区名为 BACKUP_OS；镜像目录为 partimag。新建隐藏镜像分区大小为 Windows NTFS 已用容量的 60%，以 1024 进制的 GB 为单位向上取整到 10 GB 档位，不保证镜像能装下；备份失败时保留未完成标记并尝试重启。
- 首次成功备份会设为 BACKUP_OS；后续备份使用 auto_backup_时间戳。恢复仅使用 BACKUP_OS；找不到时中止并重启，不会自动选取或改名其他镜像。
- 恢复前执行 Clonezilla 镜像检查；检查通过后自动覆盖 Windows 目标分区，完成后自动重启，不再等待用户确认。备份后不执行额外镜像检查。
- 当前只备份和还原 Windows 所在分区，不恢复原 Windows ESP、整个 GPT 或其他分区；不能保证修复损坏的引导分区。
- 已有 BACKUP_OS 时程序不会自动创建新分区；可查看已有镜像及可用操作。日志在项目 logs 文件夹和可访问的 BACKUP_OS/recovery_logs 中。

三、限制
- 要求 x86-64、UEFI、GPT、关闭 Secure Boot；不支持 BitLocker 加密分区。
- GRUB 仅列出活动且可解析、以 GPT 分区 GUID 定位、由 GRUB 文件系统驱动可读取的 EFI 文件启动项。网络、固件内建、无 GPT GUID、非 ASCII EFI 路径及不受支持的文件系统会跳过；macOS 的 APFS 等不保证可用。重复的 GPT 分区 GUID 也会被跳过。
- 分区创建或部署中途失败时，已经执行的改动不会自动撤销。
- 当前 F12 链式启动修复已由用户在一台 Windows 10 虚拟机验证；不能据此保证其他机器及所有备份恢复场景均已验证。
- 程序使用 Windows PowerShell 和 .NET Framework 4.x，不需要安装 Python。构建源码需要系统中的 .NET Framework C# 编译器。

四、文件
- RecoveryConsole.exe：管理员入口；RecoveryConsole.Worker.exe、FirmwareHelper.exe 与 installer.ps1 是运行所需组件。
- assets：GRUB EFI、启动和恢复脚本。resources/live：Clonezilla Linux 内核、initrd 和 squashfs。
- source：C#、PowerShell、GRUB 配置和恢复脚本源码。build-experimental.ps1 重新编译 Windows 程序并同步源码脚本；不会重新编译 GRUB 或下载 Clonezilla。
- 本项目包含第三方 Clonezilla Live 和 GRUB 文件。分发时需遵守其各组件许可，并提供适用源码及许可证信息；请以实际 Clonezilla 版本的上游发布资料为准。

- 新部署使用卷 GUID 路径访问 ESP，不主动分配盘符。如果系统意外分配盘符，安装会停止并提示人工检查。已有盘符保持不变。

多系统扫描版是新构建的实验 GRUB，尚未经过虚拟机或实机端到端验证。不要在重要数据或唯一可启动系统上部署。source 包含新增扫描模块、GRUB 2.12 源码与独立 GRUB 构建脚本。

界面中的 GB 按 1 GB = 1024³ 字节计算；显示的是分区申请大小。格式化后 Windows 显示的文件系统容量可能略小。

