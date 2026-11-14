#!/usr/bin/env bash
# Build the GRUB EFI binary in a temporary directory; no disks are modified.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
tar -xf "$project/source/grub-2.12.tar.xz" -C "$work"
src="$work/grub-2.12"
cp "$project/source/grub-scan-windows.c" "$src/grub-core/commands/efi/lsefi.c"
# Display the EFI StartImage status instead of the generic unknown error.
python3 - "$src/grub-core/loader/efi/chainloader.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
old = 'grub_error (GRUB_ERR_BAD_OS, "unknown error");'
new = 'grub_error (GRUB_ERR_BAD_OS, "UEFI StartImage status: 0x%llx", (unsigned long long) status);'
if s.count(old) != 1: raise SystemExit('Unexpected GRUB source; no output written')
p.write_text(s.replace(old, new))
PY
cd "$src"
./configure --with-platform=efi --target=x86_64 --disable-werror --disable-nls
# The upstream release tarball lacks this optional list in this build environment.
touch grub-core/extra_deps.lst
make -j"$(nproc)"
./grub-mkstandalone --format=x86_64-efi --directory=grub-core \
  --output="$work/grubx64.efi" \
  --modules="part_gpt part_msdos fat ntfs linux chain normal search_fs_file lsefi test" \
  "boot/grub/grub.cfg=$project/source/grub-bootstrap.cfg"
cp "$work/grubx64.efi" "$project/assets/grubx64.efi"
printf '%s\n' 'Built GRUB into assets/grubx64.efi.'
