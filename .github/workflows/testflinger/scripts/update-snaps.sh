#!/usr/bin/env bash
set -e

# On UC22, the kernel, core, snapd snaps get refreshed right after first boot,
# causing unexpected errors and triggering a reboot
# On UC24, the auto refresh starts after a delay while testing
# Hold automatic refreshes until we can manually trigger and handle the restarts
ssh $DEVICE_USER@$DEVICE_IP "sudo snap refresh --hold=3h --no-wait"

timeout=$((20 * 60))  # 20 minutes in seconds
interval=30
elapsed=0
while true; do
  echo "Force refresh all snaps"
  # This command will fail if the machine is offline or restarting
  ssh $DEVICE_USER@$DEVICE_IP "sudo snap refresh --no-wait" || true

  # If all changes have been applied, check for component support
  if ssh $DEVICE_USER@$DEVICE_IP "$(< $SCRIPTS/check-snap-changes.sh)"; then
    echo "Checking snapd support for components"
    if ssh $DEVICE_USER@$DEVICE_IP "snap components"; then
      echo "Snapd has component support"
      break
    else
      echo "Snapd does not support components. Retrying refresh after delay..."
    fi
  fi

  if (( elapsed >= timeout )); then
    echo "Timeout waiting for snaps to update"
    exit 1
  fi

  sleep $interval
  elapsed=$((elapsed + interval))
done
