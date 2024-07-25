#!/usr/bin/env bash

sudo apt install -y netcat

while ! nc -z $1 $2; do   
  echo "Waiting for $1:$2 ..."
  sleep 10
done