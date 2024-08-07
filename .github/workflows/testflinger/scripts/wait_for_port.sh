#!/usr/bin/env bash
set -ex

# install dependencies
sudo apt install -y netcat

# check connection to the device
while ! nc -z $1 $2; do
  echo "Waiting for $1:$2 ..."
  sleep 10
done
