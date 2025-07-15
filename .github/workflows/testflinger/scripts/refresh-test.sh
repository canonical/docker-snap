#!/usr/bin/env bash

set -eEuo pipefail

trap 'echo "error, sad day ($?)"; sleep 1; sudo snap logs -n=40 docker.dockerd; sleep 1; sudo tail -n20 /var/log/*.log; sudo dmesg | tail -n20; sudo journalctl --no-pager | grep docker' ERR

cleanup() (
  set -x
  sudo snap remove --purge docker
)

revert_docker()(
  set -x
  sudo snap revert docker

  # Reverting doesn't change the channel, so we need to switch back to stable
  sudo snap switch docker --stable

  sudo snap list docker
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

install_docker()(
  set -x
  sudo snap install docker
)

setup() (
  install_docker

  # Wait for docker to be fully initialized
  sleep 5 

  cat <<'EOF' >run-vector.sh
#!/bin/bash -eu

while true; do
  /tmp/vectorAdd
  sleep 1
done
EOF
  chmod +x run-vector.sh
)

check_container() (
  # Wait for the restart policy to take effect
  # See: https://docs.docker.com/engine/containers/start-containers-automatically/#restart-policy-details
  sleep 10

  # Check if the container is running
  CONTAINER_COUNT=$(sudo docker ps -q | wc -l)
  if [ "$CONTAINER_COUNT" -ne 1 ]; then
    echo "Expected 1 container, found $CONTAINER_COUNT"
    sudo docker ps -a
    exit 1
  fi
)

run_workload() (
  set -x
  sudo docker run --restart=always --detach -v $(pwd)/run-vector.sh:/run-vector.sh:ro --entrypoint=/run-vector.sh --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda10.2
)

main() {
  cleanup

  setup

  run_workload

  check_container

  refresh_docker

  check_container

  revert_docker

  check_container

  echo "Docker snap successfully refreshed and container is still running."
}

main
