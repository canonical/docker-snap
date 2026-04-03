#!/bin/bash

# Invoked in each system before running any test
# Learn more about preparing and restoring: https://github.com/canonical/spread?tab=readme-ov-file#preparing

source "$SCRIPTS_PATH/common.sh"

echo "Installing snapd"
apt-get update && apt-get install snapd -y

echo "Removing docker (if already installed)"
snap remove docker --purge || true

# If $SNAP_CHANNEL was provided, install docker from the store:
if [ -n "$SNAP_CHANNEL" ] ; then
    echo "Installing docker from channel: $SNAP_CHANNEL"
    snap install docker --channel=$SNAP_CHANNEL
else
    echo "No SNAP_CHANNEL provided, looking for a local build of docker in $(pwd)"

    if [ -e ./docker_*.snap ] ; then
        echo "Snap found, installing it"
        snap install ./docker_*.snap --dangerous

        # Also install components, if any
        snap install ./docker_*.comp --dangerous || true

        echo "Connecting interfaces"
        snap connect docker:docker-cli        docker:docker-daemon  
        snap connect docker:privileged        :docker-support 
        snap connect docker:support           :docker-support
        snap connect docker:firewall-control
        snap connect docker:home
        snap connect docker:network-control

        # Restart docker and keep on retrying on failure
        echo "Restarting docker"
        until snap restart docker; do sleep 1; done
    else
        ERROR "\
Could not install docker because SNAP_CHANNEL was not provided and no docker_*.snap file was found in the project directory.\n\
Please compile docker before running tests by executing\n\
    $ snapcraft pack\n\
Or specify a store channel, e.g. \n\
    $ export SNAP_CHANNEL=latest/edge\
"
    fi
fi

# Wait for docker to become online, with a 1 minute timeout
wait_for_docker # from common.sh

echo "Preparation completed"
