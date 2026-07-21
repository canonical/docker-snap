#!/bin/bash

run_retry_command() {
  local RETRIES=30
  local DELAY=6
  local n=1
  until "$@"; do
    if [[ $n -ge $RETRIES ]]; then
      ERROR "Command failed after $RETRIES attempts: $*"
    fi
    echo "Command failed (attempt $n/$RETRIES): $*. Retrying in $DELAY seconds..."
    ((n++))
    sleep $DELAY
  done
}

wait_for_docker() {
    echo "Waiting for docker to become available..."
    run_retry_command docker info
}

restart_docker() {
    echo "Restarting docker daemon..."
    run_retry_command sudo snap restart docker
}
