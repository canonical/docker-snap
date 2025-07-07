#!/usr/bin/env bash

set -e

cleanup() (
  sudo snap remove --purge docker
)

refresh_docker() (
  # SNAP_CHANNEL may be set by the caller, or replaced in CI
  DOCKER_SNAP_CHANNEL=$SNAP_CHANNEL
  if [[ -z "$DOCKER_SNAP_CHANNEL" ]]; then
    DOCKER_SNAP_CHANNEL="latest/edge"
  fi

  set -x

  # refresh docker-snap
  sudo snap refresh docker --channel="$DOCKER_SNAP_CHANNEL"
)


setup()(
  set -x
  sudo snap install docker
  sleep 5 # Wait for docker to be fully initialized

  cat << 'EOF' > run-vector.sh
#!/bin/bash -eu

while true; do
  /tmp/vectorAdd
  sleep 1
done
EOF
  chmod +x run-vector.sh
)


check_container() (
  set -x
  # Wait for the restart policy to take effect
  # See: https://docs.docker.com/engine/containers/start-containers-automatically/#restart-policy-details
  sleep 10

  # Check if the container is running
  CONTAINER_COUNT=$(sudo docker ps -q | wc -l)
  if [ "$CONTAINER_COUNT" -ne 1 ]; then
    echo "Expected 1 container, found $CONTAINER_COUNT"
    exit 1
  fi
)

main()(
  set -ex
  cleanup
  setup

  sudo docker run --restart=always --detach -v $(pwd)/run-vector.sh:/run-vector.sh:ro --entrypoint=/run-vector.sh --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda10.2

  check_container

  refresh_docker

  check_container
)

main