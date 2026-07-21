#!/bin/bash
# Sourced by the garden backend allocate hook in spread.yaml. Runs on the
# host and relies on spread injecting the ADDRESS/FATAL helpers and the
# SPREAD_* environment into the caller -- hence sourced, not executed.
set -eu

# Spread automatically injects /snap/bin to PATH. When we are
# running from the image-garden snap then SPREAD_HOST_PATH is the
# original path before such modifications were applied. Snap
# applications cannot normally run /snap/bin/* entry-points
# successfully so re-set PATH to the original value, as provided by
# snapcraft.
if [ -n "${SPREAD_HOST_PATH-}" ]; then
  PATH="${SPREAD_HOST_PATH}"
fi

export QEMU_SMP_OPTION="-smp 4"
# image-garden's default. Anything higher risks the host OOM killer:
# spread allocates every matched system concurrently, and five emulated
# guests at 3072 MiB plus qemu overhead exceed the 16 GiB of a standard
# GitHub runner. The OOM killer then reaps allocate scripts or guests
# mid-boot, which surfaces as empty "Cannot allocate" errors.
export QEMU_MEM_OPTION="-m 2048"

# Map spread system architecture
SPREAD_SYSTEM=${SPREAD_SYSTEM/%amd64/x86_64}  # maps "amd64" to "x86_64"
SPREAD_SYSTEM=${SPREAD_SYSTEM/%arm64/aarch64} # maps "arm64" to "aarch64"

GARDEN_SYSTEM="${SPREAD_SYSTEM/-plus-/+}"

HOST_ARCH="${ARCH:-$(uname -m)}"
SYSTEM_ARCH="${SPREAD_SYSTEM##*.}"

# The qemu 'virt' machine used for aarch64 -- and only that machine --
# requires the EFI variable store (pflash unit 1) to be exactly 64 MiB.
# image-garden has been observed to emit a wrong-sized (or empty) vars
# image there, which makes qemu refuse to start with:
#   cfi.pflash01 device '/machine/virt.flash1' requires 67108864 bytes,
#   pflash1 block backend provides <N> bytes
# Check and repair this *before* attempting to boot, not after a slow
# failed attempt: building the vars image doesn't require booting
# anything, so this costs seconds rather than eating into the allocate
# watchdog below. Strictly aarch64-scoped: x86_64's q35 machine caps
# combined firmware at 8 MiB, so inflating its OVMF vars file to 64 MiB
# makes qemu refuse to start instead.
if [ "$SYSTEM_ARCH" = "aarch64" ]; then
  EFI_VARS_SIZE=67108864 # 64 MiB
  efi_vars_img=".image-garden/${SPREAD_SYSTEM}.efi-vars.img"

  image-garden make "${GARDEN_SYSTEM}.efi-vars.img" || true
  if [ -f "$efi_vars_img" ] && [ "$(stat -c%s "$efi_vars_img")" != "$EFI_VARS_SIZE" ]; then
    echo "Repairing wrong-sized EFI vars image: $efi_vars_img"
    # qemu-img rather than truncate: binaries not shipped inside the
    # image-garden snap (truncate, timeout, ...) cannot be executed from
    # the host under confinement. qemu-img is what image-garden itself
    # uses, so it is always available. Guarded so a failed repair falls
    # through to a normal allocation failure instead of killing the
    # script under set -e.
    qemu-img resize -f raw "$efi_vars_img" "$EFI_VARS_SIZE" || true
  fi
fi

# Limit concurrent emulated guest boots with a small flock semaphore.
# Five TCG guests booting at once starve udev inside the guests badly
# enough that systemd's 92-second device timeout fires: the boot-logs
# artifact shows /dev/disk/by-label/BOOT never appearing on
# ubuntu-cloud-26.04, failing local-fs.target and dropping the guest
# into emergency mode. Two boots at a time keep each guest fast enough
# to win that race. Only applies to emulated or non-KVM boots; native
# KVM boots are quick and skip the queue entirely.
#
# The slot is held on fd 9 from just before image-garden allocate until
# sshd answers (or the poll gives up). The fd is explicitly closed
# (9>&-) for spawned children: a daemonized qemu inheriting it would
# hold the slot for the lifetime of the VM. If no slot frees up within
# the cap, continue without one -- a congested host degrades to the old
# unserialized behaviour rather than dying while queued.
BOOT_SLOTS=2
BOOT_SLOT_WAIT_SECS=900

acquire_boot_slot() {
  local waited=0
  local i
  while [ "$waited" -lt "$BOOT_SLOT_WAIT_SECS" ]; do
    i=1
    while [ "$i" -le "$BOOT_SLOTS" ]; do
      exec 9>"${TMPDIR:-/tmp}/spread-boot-slot-$i.lock"
      if flock -n 9; then
        echo "Acquired boot slot $i"
        return 0
      fi
      exec 9>&- || true
      i=$((i+1))
    done
    sleep 10
    waited=$((waited+10))
  done
  echo "No boot slot free after ${BOOT_SLOT_WAIT_SECS}s; booting without one"
  return 0
}

release_boot_slot() {
  exec 9>&- 2>/dev/null || true
}

# Bound the attempt. A VM that never becomes reachable (for example one
# that boots into systemd emergency mode under emulation) would otherwise
# hang the allocation until GitHub kills the whole job at its 6h ceiling.
# timeout(1) can't do this here: it isn't shipped in the image-garden
# snap and the host binary is blocked by confinement, so a background
# killer stands in. Killing the killer once allocate returns stops it
# ever firing at a reused pid; its leftover sleep is harmless on the
# ephemeral runner. Stays under kill-timeout (45m) with the poll below,
# so spread never preempts our FATAL. The 9>&- closes the boot-slot fd
# so a daemonized qemu can't inherit and hold it.
allocate() {
  local pid killer status=0
  image-garden allocate "$GARDEN_SYSTEM" 9>&- &
  pid=$!
  ( sleep 30m; kill "$pid" 2>/dev/null ) 9>&- &
  killer=$!
  wait "$pid" || status=$?
  kill "$killer" 2>/dev/null || true
  return "$status"
}

if [ "$HOST_ARCH" != "$SYSTEM_ARCH" ] || [ ! -e /dev/kvm ]; then
  acquire_boot_slot
fi

if ! OUT="$(allocate)" || [ -z "$OUT" ]; then
  # FATAL (not ERROR) so spread does not retry into the 6h ceiling.
  # The script exits here, which also releases any held boot slot.
  FATAL "image-garden could not allocate $SPREAD_SYSTEM"
fi

if [ "$HOST_ARCH" != "$SYSTEM_ARCH" ] || [ ! -e /dev/kvm ]; then
  # Spread's ssh-ready timeout is a fixed 5 minutes, which emulated or
  # non-KVM boots can overrun. This used to be a flat "sleep 5m", but
  # image-garden tends to hand out the address only once sshd is already
  # answering, making most of that sleep pure waste. Poll for an ssh
  # banner instead and hand over as soon as the daemon responds, with a
  # hard upper bound (currently 10 minutes) to avoid hanging indefinitely.
  # Uses bash /dev/tcp and the read builtin rather than external tools
  # (the timeout binary, for one, is denied by confinement in the image-garden snap environment).
  ssh_host="${OUT%:*}"
  ssh_port="${OUT##*:}"
  ssh_banner_ready() {
    (
      exec 3<>"/dev/tcp/${ssh_host}/${ssh_port}" || exit 1
      banner=""
      IFS= read -r -t 10 -n 4 banner <&3 || true
      [ "$banner" = "SSH-" ]
    ) 2>/dev/null
  }
  # Cap of 120 x 5s = 10 minutes. Falling through with sshd still down
  # is worse than waiting: spread only grants one minute of connection
  # attempts after ADDRESS, then discards the whole system (observed
  # with ubuntu-cloud-26.04 booting alongside four other guests).
  # Budget-wise this still fits: one 30m30s allocate attempt plus 10m
  # of polling stays under the 45m kill-timeout.
  attempts=0
  while [ "$attempts" -lt 120 ]; do
    if ssh_banner_ready; then
      echo "ssh is answering on $OUT"
      break
    fi
    attempts=$((attempts + 1))
    sleep 5
  done
  if [ "$attempts" -ge 120 ]; then
    release_boot_slot
    FATAL "ssh did not become ready on $OUT"
  fi
fi

release_boot_slot

ADDRESS "$OUT"
