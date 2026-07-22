#!/bin/bash
# Prepare or repair the firmware images image-garden needs for the given
# system, working around image-garden snap packaging issues. Used by the
# spread allocate hook; must run before anything boots (or, for riscv64,
# before image-garden's make ever runs). No-op for other architectures.
#
# - aarch64: image-garden emits a ~2.8 MiB EFI vars image, but the qemu
#   'virt' machine requires exactly 64 MiB:
#     cfi.pflash01 device '/machine/virt.flash1' requires 67108864 bytes
#   Grow it in place. Strictly aarch64: x86_64's q35 caps combined firmware
#   at 8 MiB, so its vars file must NOT be grown.
#
# - riscv64: image-garden's own makefile pads the flash images with
#   truncate(1), which is not shipped in the snap and is blocked by
#   confinement ("/usr/bin/truncate: Permission denied", make Error 126).
#   Pre-build correctly sized images here so that recipe never runs.
#
# qemu-img rather than truncate throughout: binaries not shipped inside the
# image-garden snap cannot be executed from the host under confinement.
set -eu

garden_system="${1:?usage: prepare-firmware.sh <image-garden-system>}"

case "$garden_system" in
  *.aarch64)
    efi_vars_size=67108864 # 64 MiB
    efi_vars_img=".image-garden/${garden_system}.efi-vars.img"

    image-garden make "${garden_system}.efi-vars.img" || true
    if [ -f "$efi_vars_img" ] && [ "$(stat -c%s "$efi_vars_img")" != "$efi_vars_size" ]; then
      echo "Repairing wrong-sized EFI vars image: $efi_vars_img"
      qemu-img resize -f raw "$efi_vars_img" "$efi_vars_size" || true
    fi
    ;;
  *.riscv64)
    flash_size=32M # the riscv64 vm requires 32 MiB flash images
    mkdir -p .image-garden
    for part in code vars; do
      src="/snap/image-garden/current/components/qemu-riscv64/share/qemu/edk2-riscv-${part}.fd"
      dst=".image-garden/efi-${part}.riscv64.img"
      if [ -f "$src" ] && [ ! -f "$dst" ]; then
        echo "Pre-building $dst (snap-safe stand-in for image-garden's truncate)"
        # Plain cp: the fresh mtime makes make consider the target up to date.
        cp "$src" "$dst"
        qemu-img resize -f raw "$dst" "$flash_size"
      fi
    done
    ;;
esac
