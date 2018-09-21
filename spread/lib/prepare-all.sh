#!/bin/bash

# install jq
apt update && apt install jq snapd -y

# make the docker group
addgroup --system docker
adduser $USER docker
newgrp docker

# make sure that snapd is installed and available
snap install hello-world

# enable layouts
sudo snap set core experimental.layouts=true

# We don't have to build a snap when we should use one from a
# channel
if [ -n "$SNAP_CHANNEL" ] ; then
	exit 0
fi

# If there is a docker snap prebuilt for us, lets take
# that one to speed things up.
if [ -e /home/docker/docker_*_amd64.snap ] ; then
	exit 0
fi

echo "Not trying to build docker on the test target: provide a pre-built snap"
test -e /home/docker/docker_*_amd64.snap
