#!/usr/bin/env bash
set -e

# Trigger a refresh of all the snaps. This will likely cause the system to restart a few times.
echo "Force refresh all snaps"
ssh $DEVICE_USER@$DEVICE_IP "sudo snap refresh --no-wait" || true

max_iterations=30
interval=60 # seconds
iteration=0
while true; do
  # Check if server is online and there are no snapd changes in progress
  if ssh $DEVICE_USER@$DEVICE_IP "$(<$SCRIPTS/check-snap-changes.sh)"; then
    echo "Checking snapd version"
    ssh $DEVICE_USER@$DEVICE_IP "snap list snapd"

    echo "Checking snapd support for components"
    if ssh $DEVICE_USER@$DEVICE_IP "snap components"; then
      echo "Snapd has component support"
      break
    else
      echo "Snapd does not support components"

      if ssh $DEVICE_USER@$DEVICE_IP "[ -f /run/snapd/reboot-required ]"; then
        echo "A restart is pending"
        ssh $DEVICE_USER@$DEVICE_IP "(sleep 3 && sudo reboot) &"
      else
        echo "Trying to refresh snaps again"
        ssh $DEVICE_USER@$DEVICE_IP "sudo snap refresh --no-wait"
      fi
    fi
  fi

  # Timeout and fail if it takes too long
  iteration=$((iteration + 1))
  if ((iteration >= max_iterations)); then
    echo "Timeout waiting for snaps to update"
    exit 1
  fi

  # Server is either offline, or there are still snapd changes in progress, wait before checking again
  sleep $interval
done
