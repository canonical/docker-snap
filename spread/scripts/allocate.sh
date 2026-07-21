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

# One emulated guest per runner (the CI matrix fans systems out into separate
# jobs), so there is no contention to budget memory against.
export QEMU_SMP_OPTION="-smp 4"
export QEMU_MEM_OPTION="-m 3072"

# Map spread system architecture
SPREAD_SYSTEM=${SPREAD_SYSTEM/%amd64/x86_64}  # maps "amd64" to "x86_64"
SPREAD_SYSTEM=${SPREAD_SYSTEM/%arm64/aarch64} # maps "arm64" to "aarch64"

GARDEN_SYSTEM="${SPREAD_SYSTEM/-plus-/+}"

HOST_ARCH="${ARCH:-$(uname -m)}"
SYSTEM_ARCH="${SPREAD_SYSTEM##*.}"

# Repair image-garden's wrong-sized aarch64 EFI vars image before booting
# (see the script for the why). No-op on other arches.
bash spread/scripts/repair-efi-vars.sh "$GARDEN_SYSTEM"

# A VM that never becomes reachable (for example one that boots into systemd
# emergency mode under emulation) would otherwise hang the allocation until
# GitHub kills the whole job at its 6h ceiling. timeout isn't shipped in the
# image-garden snap and the host binary is blocked by confinement, so we write
# our own little watchdog, bounding the attempt below spread's kill-timeout so
# spread never preempts our FATAL.
#
# NOTE: the killer's stdout/stderr are redirected to /dev/null. Otherwise its
#       orphaned sleep would inherit and hold spread's output pipe open, and
#       spread waits for that pipe to close before moving on.
allocate() {
  local pid killer status=0
  image-garden allocate "$GARDEN_SYSTEM" &
  pid=$!
  ( sleep 30m; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  killer=$!
  wait "$pid" || status=$?
  kill "$killer" 2>/dev/null || true
  return "$status"
}

if ! OUT="$(allocate)" || [ -z "$OUT" ]; then
  FATAL "image-garden could not allocate $SPREAD_SYSTEM"
fi

if [ "$HOST_ARCH" != "$SYSTEM_ARCH" ] || [ ! -e /dev/kvm ]; then
  # image-garden hands out the address once the port-forward exists, which under
  # emulation can be well before sshd actually answers. Poll for the banner and
  # hand over as soon as the daemon responds, with a hard 10-minute upper bound.
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
    FATAL "ssh did not become ready on $OUT"
  fi
fi

ADDRESS "$OUT"
