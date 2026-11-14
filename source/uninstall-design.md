# Uninstall design (not implemented)

- Identify the tool ESP by its GPT type and by the presence of EFI/clonezilla/recovery.conf and grubx64.efi; do not identify it by the generic ESP label alone.
- Parse recovery.conf without executing it and match store_partuuid against exactly one GPT partition labelled BACKUP_OS. Refuse ambiguity, missing configuration, or matching the Windows system or boot partition.
- Enumerate UEFI Boot#### variables, matching both the ESP partition GUID and the exact EFI/clonezilla/grubx64.efi path. Never remove entries based only on their description.
- Show disk numbers, partition numbers, sizes, GUIDs, image deletion consequences, and matching boot entries. Require explicit confirmation before making changes.
- Re-read and compare disk identities, partition GUIDs, GPT types, offsets and sizes, plus the matching firmware entries immediately before mutation. Abort on any mismatch.
- Remove only matching UEFI entries; preserve the rest of BootOrder and handle BootNext pointing to a removed entry. Report partial completion and errors explicitly.
- Delete the validated tool ESP and backup partition only. Leave unallocated space; do not resize other volumes. Deleting the backup partition permanently removes its images.
- Keep a detailed log and stop safely on any failure. Do not treat a partial uninstall as complete.
