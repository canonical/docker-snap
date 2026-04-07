#!/bin/bash

# Invoked in each system before running any test
# Learn more about preparing and restoring: https://github.com/canonical/spread?tab=readme-ov-file#preparing

source "$SCRIPTS_PATH/common.sh"

select_snap_file() {
    # Build a list of local snap artifacts matching the pattern "docker_*.snap" in the current directory
    shopt -s nullglob # make the glob expand to an empty array instead of itself if there are no matches
    local snap_files=(./docker_*.snap)
    shopt -u nullglob

    if [ ${#snap_files[@]} -eq 0 ] ; then
        # there are no docker_*.snap files in the current directory
        ERROR "No docker_*.snap file was found in the project directory. Please build docker using 'snapcraft pack' or specify SNAP_CHANNEL to install from the store."
    fi

    local selected_snap=""
    if [ ${#snap_files[@]} -eq 1 ] ; then
        # there is exactly one docker_*.snap file in the current directory, use it
        selected_snap="${snap_files[0]}"
    else
        ERROR "Multiple docker snap files were found and SNAP_FILE was not provided. Please set SNAP_FILE to the file you want to install."
    fi

    echo "$selected_snap"
}

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
    echo "No SNAP_CHANNEL nor SNAP_FILE provided, looking for a local build of docker in $(pwd)"

    selected_snap="$(select_snap_file)"
    install_snap_file "$selected_snap"
fi

# Wait for docker to become online, with a 1 minute timeout
wait_for_docker # from common.sh

echo "Preparation completed"
