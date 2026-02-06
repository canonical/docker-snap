#!/usr/bin/env bash
set -e

# Trigger a refresh of all the snaps. This will likely cause the system to restart a few times.
echo "Force refresh all snaps"
ssh $DEVICE_USER@$DEVICE_IP "sudo snap refresh --no-wait" || true

# Due to an issue with kernel components and snapd <2.74, we need to update to snapd from the beta channel.
ssh $DEVICE_USER@$DEVICE_IP "sudo snap refresh snapd --channel=latest/beta --no-wait" || true

max_iterations=10 # x interval = 30 minutes
interval=60 # seconds
iteration=0
while true; do
  # Check if server is online and there are no snapd changes in progress
  if ssh $DEVICE_USER@$DEVICE_IP "$(< $SCRIPTS/check-snap-changes.sh)"; then
    echo "Checking snapd support for components"
    if ssh $DEVICE_USER@$DEVICE_IP "snap components"; then
      echo "Snapd has component support"
      break
    else
      echo "Snapd does not support components. A reboot is likely required"
      ssh $DEVICE_USER@$DEVICE_IP "(sleep 3 && sudo reboot) &"
    fi
  fi

  # Timeout and fail if it takes too long
  iteration=$((iteration + 1))
  if (( iteration >= max_iterations )); then
    echo "Timeout waiting for snaps to update"
    exit 1
  fi

  # Server is either offline, or there are still snapd changes in progress, wait before checking again
  sleep $interval
done
