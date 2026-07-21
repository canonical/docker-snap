#!/bin/bash

# Invoked in each system before running any test
# Learn more about preparing and restoring: https://github.com/canonical/spread?tab=readme-ov-file#preparing

source "$SCRIPTS_PATH/common.sh"

if command -v apt-get >/dev/null; then
    echo "Installing snapd"
    sudo apt-get update && sudo apt-get install snapd -y
else
    # Ubuntu Core: snapd is the OS, nothing to install. The image seeds from an
    # old recovery system, so the first boot wants to auto-refresh the boot
    # snaps (kernel/base/snapd) -- and on Core that reboots the machine, which
    # drops spread's session mid-prepare and aborts every task ("snapd is
    # about to reboot the system"). Settle the seed and hold refreshes for the
    # lifetime of this ephemeral guest.
    echo "Ubuntu Core detected; holding snap refreshes"
    sudo snap wait system seed.loaded
    sudo snap refresh --hold || true
    sudo snap abort --last=auto-refresh 2>/dev/null || true
fi

echo "Removing docker (if already installed)"
sudo snap remove docker --purge || true

if [ -n "$SNAP_CHANNEL" ] ; then
    # If $SNAP_CHANNEL was provided, install docker from the store
    echo "Installing docker from channel: $SNAP_CHANNEL"
    sudo snap install docker --channel=$SNAP_CHANNEL
elif [ -n "$SNAP_FILE" ] ; then
    echo "Installing local snap: $SNAP_FILE"
    sudo snap install "$SNAP_FILE" --dangerous

    echo "Connecting interfaces"

    # sudo snap connect docker:gpu-2404 mesa-2404:gpu-2404 || true # not connected because we don't do any graphics tests
    sudo snap connect docker:docker-cli        docker:docker-daemon
    sudo snap connect docker:privileged
    sudo snap connect docker:support
    sudo snap connect docker:firewall-control
    sudo snap connect docker:home
    sudo snap connect docker:network
    sudo snap connect docker:network-bind
    sudo snap connect docker:network-control
    sudo snap connect docker:opengl

    # Restart docker and keep on retrying on failure
    echo "Restarting docker"
    restart_docker # from common.sh
else
    ERROR "No SNAP_CHANNEL nor SNAP_FILE provided"
fi

# Wait for docker to become online, with a 1 minute timeout
wait_for_docker # from common.sh

echo "Preparation completed"
