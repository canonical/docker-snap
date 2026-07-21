#!/bin/bash
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
export QEMU_MEM_OPTION="-m 2048"

# Map spread system architecture
SPREAD_SYSTEM=${SPREAD_SYSTEM/%amd64/x86_64}  # maps "amd64" to "x86_64"
SPREAD_SYSTEM=${SPREAD_SYSTEM/%arm64/aarch64} # maps "arm64" to "aarch64"

GARDEN_SYSTEM="${SPREAD_SYSTEM/-plus-/+}"

HOST_ARCH="${ARCH:-$(uname -m)}"
SYSTEM_ARCH="${SPREAD_SYSTEM##*.}"

# Repair image-garden's wrong-sized aarch64 EFI vars image before booting
# (see the script for the why). No-op on other arches.
bash spread/scripts/repair-efi-vars.sh "$GARDEN_SYSTEM"

# Limit concurrent emulated guest boots with a small flock semaphore. This only
# matters on kvm-less hosts. Otherwise the concurrent emulated boot causes flaky
# inner systemd boot timeout and drops the guest into the emergency mode. 
# The slot is held on fd 9 from just before image-garden allocate until
# sshd answers. The fd is explicitly closed (9>&-) for spawned children:
# a daemonized qemu inheriting it would hold the slot for the lifetime of
# the VM. If no slot frees up within the cap, continue anyway. At worst we
# degrade back to unsynchronised boot, and fail the tests. *This will never
# result in false-positive tests*.
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

# A VM that never becomes reachable (for example one that boots into systemd
# emergency mode under emulation) would otherwise hang the allocation until
# GitHub kills the whole job at its 6h ceiling. timeout isn't shipped in the
# image-garden snap and the host binary is blocked by confinement, so we write
# our own little watchdog. The timeout stays under spread's kill-timeout (45m)
# so spread should never preempt our FATAL. The 9>&- closes the boot-slot fd so a
# daemonized qemu can't inherit and hold it.
#
# NOTE: The watchdogs's stdout/stderr are redirected to /dev/null. Otherwise the
#       orphaned sleep would inherit and hold spread's output pipe open, and
#       spread waits for that pipe to close before moving on.
allocate() {
  local pid killer status=0
  image-garden allocate "$GARDEN_SYSTEM" 9>&- &
  pid=$!
  ( sleep 30m; kill "$pid" 2>/dev/null ) 9>&- >/dev/null 2>&1 &
  killer=$!
  wait "$pid" || status=$?
  kill "$killer" 2>/dev/null || true
  return "$status"
}

if [ "$HOST_ARCH" != "$SYSTEM_ARCH" ] || [ ! -e /dev/kvm ]; then
  acquire_boot_slot
fi

if ! OUT="$(allocate)" || [ -z "$OUT" ]; then
  FATAL "image-garden could not allocate $SPREAD_SYSTEM"
fi

if [ "$HOST_ARCH" != "$SYSTEM_ARCH" ] || [ ! -e /dev/kvm ]; then
  # Poll for an ssh banner and hand over as soon as the daemon responds, with a
  # hard upper bound (10 min) to avoid hanging indefinitely.
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
