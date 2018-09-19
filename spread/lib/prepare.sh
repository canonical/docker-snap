#!/bin/bash

# Pre-install docker
if [ -n "$SNAP_CHANNEL" ] ; then
	# Don't reinstall if we have it installed already
	if ! snap list | grep docker ; then
		snap install --$SNAP_CHANNEL docker
        snap connect docker:home :home
	fi
else
	# Install prebuilt docker snap
	snap install --dangerous /home/docker/docker_*_amd64.snap
	# As we have a snap which we build locally its unasserted and therefore
	# we don't have any snap-declarations in place and need to manually
	# connect all plugs.
	snap connect docker:privileged :docker-support
    snap connect docker:docker-support
    snap connect docker:firewall-control :firewall-control
    snap connect docker:network :network
    snap connect docker:network-bind :network-bind
    snap connect docker:docker-cli docker:docker-daemon
    snap connect docker:home :home

	# finally we also need to adjust docker's storage driver to be overlay
	# and also set the log level to debug
	# CONFIG_FILE=/var/snap/docker/current/config/daemon.json
	# echo "updating daemon config file options"
	# echo "before:"
	# cat $CONFIG_FILE
	# cat $CONFIG_FILE | jq '."storage-driver" = "overlay" | ."log-level" = "debug"'

	# echo "after:"
	# cat $CONFIG_FILE
	snap restart docker	
	# wait for the docker daemon to finish coming online
	sleep 10
fi

# Remove any existing state archive from other test suites
rm -f $SPREAD_PATH/snapd-state.tar.gz
rm -f $SPREAD_PATH/docker-state.tar.gz

# Snapshot of the current snapd state for a later restore
if [ ! -f $SPREAD_PATH/snapd-state.tar.gz ] ; then
	sudo systemctl stop snapd.service snapd.socket
	tar czfP $SPREAD_PATH/snapd-state.tar.gz /var/lib/snapd
	sudo systemctl start snapd.socket
fi

# And also snapshot current docker's state
if [ ! -f $SPREAD_PATH/docker-state.tar.gz ] ; then
    sudo systemctl stop snap.docker.dockerd
    tar czfP $SPREAD_PATH/docker-state.tar.gz /var/snap/docker
    sudo systemctl start snap.docker.dockerd
fi
