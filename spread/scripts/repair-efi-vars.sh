#!/bin/bash
# Ensure the aarch64 EFI variable store for the given image-garden system is
# the 64 MiB the qemu 'virt' machine requires. image-garden emits a wrong-sized
# (~2.8 MiB) vars image, which makes qemu refuse to start with:
#   cfi.pflash01 device '/machine/virt.flash1' requires 67108864 bytes,
#   pflash1 block backend provides <N> bytes
# Must run before any boot of that system. No-op for non-aarch64 systems --
# x86_64's q35 caps combined firmware at 8 MiB, so its vars file must NOT be
# grown. Used by both the spread allocate hook and the CI image-build job.
#
# qemu-img rather than truncate: binaries not shipped in the image-garden snap
# (truncate, timeout, ...) can't be executed from the host under confinement.
set -eu

garden_system="${1:?usage: repair-efi-vars.sh <image-garden-system>}"
case "$garden_system" in
  *.aarch64) ;;
  *) exit 0 ;;
esac

efi_vars_size=67108864 # 64 MiB
efi_vars_img=".image-garden/${garden_system}.efi-vars.img"

image-garden make "${garden_system}.efi-vars.img" || true
if [ -f "$efi_vars_img" ] && [ "$(stat -c%s "$efi_vars_img")" != "$efi_vars_size" ]; then
  echo "Repairing wrong-sized EFI vars image: $efi_vars_img"
  qemu-img resize -f raw "$efi_vars_img" "$efi_vars_size" || true
fi
