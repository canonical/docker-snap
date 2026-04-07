#!/bin/bash

# Invoked in each system before running any test
# Learn more about preparing and restoring: https://github.com/canonical/spread?tab=readme-ov-file#preparing

source "$SCRIPTS_PATH/common.sh"

install_snap_file() {
    local snap_file="$1"
    echo "Installing local snap: $snap_file"
    sudo snap install "$snap_file" --dangerous

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
}

echo "Installing snapd"
sudo apt-get update && sudo apt-get install snapd -y

echo "Removing docker (if already installed)"
sudo snap remove docker --purge || true

if [ -n "$SNAP_CHANNEL" ] ; then
    # If $SNAP_CHANNEL was provided, install docker from the store
    echo "Installing docker from channel: $SNAP_CHANNEL"
    sudo snap install docker --channel=$SNAP_CHANNEL
elif [ -n "$SNAP_FILE" ] ; then
    # SNAP_FILE was provided, check that it exists and install it
    if [ ! -e "$SNAP_FILE" ] && [ -e "./$SNAP_FILE" ] ; then
        SNAP_FILE="./$SNAP_FILE"
    fi

    if [ ! -e "$SNAP_FILE" ] ; then
        ERROR "SNAP_FILE was provided but does not exist: $SNAP_FILE"
    fi

    install_snap_file "$SNAP_FILE"
else
    ERROR "No SNAP_CHANNEL nor SNAP_FILE provided"
fi

# Wait for docker to become online, with a 1 minute timeout
wait_for_docker # from common.sh

echo "Preparation completed"
