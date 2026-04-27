#!/bin/bash

# Invoked in each system before running any test
# Learn more about preparing and restoring: https://github.com/canonical/spread?tab=readme-ov-file#preparing

source "$SCRIPTS_PATH/common.sh"

function setup_dockerhub_mirror() {
    if [ -n "$DOCKERHUB_MIRROR" ] ; then
        echo "Setting up docker mirror: $DOCKERHUB_MIRROR"

        # Using jq to set or update the registry-mirrors field in the daemon.json file
        # If the file doesn't exist, it will be created with the registry-mirrors field
        sudo mkdir -p /var/snap/docker/current/config
        docker_config_path="/var/snap/docker/current/config/daemon.json"

        if [ -f "$docker_config_path" ]; then
            echo "Updating existing docker config at $docker_config_path"

            old_docker_config_path="$docker_config_path.bak"
            sudo mv $docker_config_path $old_docker_config_path

            sudo jq --arg mirror "$DOCKERHUB_MIRROR" \
                '.["registry-mirrors"] = [$mirror]' \
                $old_docker_config_path | sudo tee $docker_config_path
        else
            echo "Creating new docker config at $docker_config_path"
            echo "{\"registry-mirrors\": [\"$DOCKERHUB_MIRROR\"]}" | sudo tee $docker_config_path
        fi
    else
        echo "No DOCKERHUB_MIRROR provided"
    fi
}

echo "Installing snapd"
sudo apt-get update && sudo apt-get install snapd -y

# this is already done by image-garden ubuntu core images, holding until the next day
# sudo snap refresh --hold=3h --no-wait

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
else
    ERROR "No SNAP_CHANNEL nor SNAP_FILE provided"
fi

setup_dockerhub_mirror()

# Restart docker and keep on retrying on failure
echo "Restarting docker"
restart_docker # from common.sh

# Wait for docker to become online, with a 1 minute timeout
wait_for_docker # from common.sh

echo "Preparation completed"
