#!/usr/bin/env bash
set -e

# TEMPORARY workaround: core26 latest/stable (rev 409, version 20260531) predates
# the chisel fix that adds /usr/bin/chroot to the base
# (https://github.com/canonical/chisel-ubuntu-core/pull/6, merged 2026-06-09),
# and the pc-kernel nvidia-*-ko component install hooks need chroot at install
# time. Refresh the base to latest/beta (version 20260629, post-fix) before
# installing the components.
# Remove this script (and its call in agent.sh) once core26 latest/stable
# serves a build >= 20260629.

# Only applies to Ubuntu Core 26 devices.
# shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
if ! ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "grep -q '^ID=ubuntu-core' /etc/os-release && grep -q '^VERSION_ID=\"26\"' /etc/os-release"; then
  echo "Not an Ubuntu Core 26 device, skipping core26 base channel switch"
  exit 0
fi

echo "Switching core26 base to latest/beta (chroot fix not yet in stable)"
# shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "sudo snap refresh core26 --channel=latest/beta --no-wait" || true

# Wait for the refresh to settle. Refreshing the boot base makes snapd reboot
# the device; the loop tolerates the connection dropping while that happens.
max_iterations=90
interval=20 # seconds
iteration=0
while true; do
  # Check if server is online and there are no snapd changes in progress
  # shellcheck disable=SC2086,SC2029  # $SSH_OPTS is an intentional multi-arg split; the script is expanded client-side by design
  if ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "$(<$SCRIPTS/check-snap-changes.sh)"; then
    # shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
    if ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "snap list core26" | grep -q "latest/beta"; then
      echo "core26 is tracking latest/beta"
      break
    fi

    echo "core26 is not yet tracking latest/beta, retrying the refresh"
    # shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
    ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "sudo snap refresh core26 --channel=latest/beta --no-wait" || true
  fi

  # Timeout and fail if it takes too long
  iteration=$((iteration + 1))
  if ((iteration >= max_iterations)); then
    echo "Timeout waiting for the core26 base channel switch"
    exit 1
  fi

  # Server is either offline (possibly rebooting into the new base), or there
  # are still snapd changes in progress; wait before checking again
  sleep $interval
done

# The whole point of the switch: the component install hooks need chroot in the
# active base. Verify it is actually there before letting setup proceed.
echo "Verifying chroot is available in the active base"
# shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
if ! ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "command -v chroot"; then
  echo "chroot is still missing from the core26 base after the beta switch."
  echo "The latest/beta build may not contain the chisel chroot fix yet."
  # shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
  ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "snap list core26" || true
  exit 1
fi
