#!/usr/bin/env bash
set -e

# The other scripts are located in the same directory as this one
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTS

echo "List attached files"
find $SCRIPTS

echo "Testing device with IP: $DEVICE_IP"

# By default ssh with user ubuntu
DEVICE_USER="${DEVICE_USER:-ubuntu}"
export DEVICE_USER
echo "Testing as user: $DEVICE_USER"

# Update preinstalled system snaps to latest versions
$SCRIPTS/update-snaps.sh
$SCRIPTS/update-snapd-beta.sh

# Install dependencies and required docker version
echo "Setup the environment on the target device"
ssh $DEVICE_USER@$DEVICE_IP "bash -s -- $SNAP_CHANNEL" < $SCRIPTS/setup.sh

# Reboot the machine to activate newly installed kernel components
# Queue reboot in background to avoid breaking the SSH connection prematurely
echo "Rebooting the device"
ssh $DEVICE_USER@$DEVICE_IP "(sleep 3 && sudo reboot) &"

# Wait for machine to start up, and also wait for docker to start
ITERATIONS=0
MAX_ITERATIONS=20 # 30 seconds, 20 times, is 10 minutes
while ! ssh $DEVICE_USER@$DEVICE_IP "sudo docker version"; do
  ITERATIONS=$((ITERATIONS + 1))
  if [ $ITERATIONS -ge $MAX_ITERATIONS ]; then
    echo "Timeout waiting for ssh server and Docker daemon."
    exit 1
  fi
  echo "Waiting for ssh server and Docker daemon ..."
  sleep 30
done

echo "Run tests"
ssh $DEVICE_USER@$DEVICE_IP "bash -s" < $SCRIPTS/test.sh

echo "Run snap refresh test"
ssh $DEVICE_USER@$DEVICE_IP "bash -s -- $SNAP_CHANNEL" < $SCRIPTS/refresh-test.sh
