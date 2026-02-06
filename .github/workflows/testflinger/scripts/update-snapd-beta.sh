#!/usr/bin/env bash
set -e

# Due to an issue with kernel components and snapd <2.74, we need to update to snapd from the beta channel.
ssh $DEVICE_USER@$DEVICE_IP "sudo snap refresh snapd --channel=latest/beta --no-wait" || true

# Wait for snapd update to finish
max_iterations=10 # x interval = 30 minutes
interval=60       # seconds
iteration=0
while true; do
  if ssh $DEVICE_USER@$DEVICE_IP "$(<$SCRIPTS/check-snap-changes.sh)"; then
    break
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
