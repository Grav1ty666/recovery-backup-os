Recovery & Backup OS 1.1.0

Windows terminal deployment tool for Clonezilla backup and recovery.
Requires x86-64 UEFI/GPT Windows. Secure Boot and BitLocker are not supported.
The launcher prefers Windows Terminal and falls back to a traditional console.

Storage options: a dedicated hidden partition, a dedicated visible partition,
or a directory on an eligible existing separate visible data partition. The
Windows system partition cannot store its own restore image. Keep the warning
file and RecoveryBackupOS directory on existing storage.

Uninstall through the management menu removes the recovery environment and its
owned backup data. In existing-volume mode, the underlying data partition is
retained. The setup uninstaller removes application files only.

Restore overwrites the Windows partition. Full-disk and original EFI partition
restore are not provided. Some features have not completed end-to-end testing.
Test on a disposable virtual machine and keep a separate backup of important data.
See ERROR-CODES.txt for troubleshooting.
