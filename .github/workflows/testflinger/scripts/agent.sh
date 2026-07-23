#!/usr/bin/env bash
set -e

# The other scripts are located in the same directory as this one
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTS

echo "List attached files"
find "$SCRIPTS"

echo "Testing device with IP: $DEVICE_IP"

# By default ssh with user ubuntu
DEVICE_USER="${DEVICE_USER:-ubuntu}"
export DEVICE_USER
echo "Testing as user: $DEVICE_USER"

# Common SSH options, inherited by the sub-scripts.
# The device under test is ephemeral and its IP is reused across provisions, so
# its host key changes; skip host-key checking to avoid hard failures.
# ConnectTimeout keeps the reboot-wait loops from blocking on TCP for minutes,
# and the ServerAlive settings drop dead sessions instead of hanging.
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=3"
export SSH_OPTS

# Update preinstalled system snaps to latest versions
"$SCRIPTS/update-snaps.sh"

# TEMPORARY: switch the core26 base to latest/beta for the chroot fix the
# nvidia component install hooks need; see the script header for the removal
# condition. No-op on other distros. Must run before setup.sh: the install
# hooks read the active (booted) base, so the switch has to complete first.
"$SCRIPTS/update-core26-beta.sh"

# Install dependencies and required docker version
echo "Setup the environment on the target device"
# shellcheck disable=SC2086,SC2029  # $SSH_OPTS is an intentional multi-arg split; remote vars expand client-side by design
ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "bash -s -- $SNAP_CHANNEL" < $SCRIPTS/setup.sh

# Record the boot id so we can tell a real reboot from a still-up pre-reboot box.
# Without this, the wait loop below can succeed before the queued reboot fires
# and run the tests on a machine that is about to go down.
# shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
BOOT_ID=$(ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "cat /proc/sys/kernel/random/boot_id")
echo "Boot id before reboot: $BOOT_ID"

# Reboot the machine to activate newly installed kernel components
# Queue reboot in background to avoid breaking the SSH connection prematurely
echo "Rebooting the device"
# shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "(sleep 3 && sudo reboot) &"

# Wait for the machine to actually reboot (boot id changed) and for docker to start.
ITERATIONS=0
MAX_ITERATIONS=20 # 30 seconds, 20 times, is 10 minutes
# shellcheck disable=SC2086,SC2029  # $SSH_OPTS is an intentional multi-arg split; $BOOT_ID expands client-side by design
while ! ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "[ \"\$(cat /proc/sys/kernel/random/boot_id)\" != \"$BOOT_ID\" ] && sudo docker version"; do
  ITERATIONS=$((ITERATIONS + 1))
  if [ $ITERATIONS -ge $MAX_ITERATIONS ]; then
    echo "Timeout waiting for ssh server and Docker daemon."
    exit 1
  fi
  echo "Waiting for ssh server and Docker daemon ..."
  sleep 30
done

echo "Run tests"
# shellcheck disable=SC2086  # $SSH_OPTS is an intentional multi-arg split
ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "bash -s" < $SCRIPTS/test.sh

echo "Run snap refresh test"
# shellcheck disable=SC2086,SC2029  # $SSH_OPTS is an intentional multi-arg split; remote vars expand client-side by design
ssh $SSH_OPTS $DEVICE_USER@$DEVICE_IP "bash -s -- $SNAP_CHANNEL" < $SCRIPTS/refresh-test.sh
