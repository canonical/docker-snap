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

  sudo snap list docker
)

refresh_docker() (
  DOCKER_SNAP_CHANNEL=$1
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
  # Wait for the restart policy to take effect, but bail as soon as exactly one
  # container is running rather than always sleeping a fixed window.
  # See: https://docs.docker.com/engine/containers/start-containers-automatically/#restart-policy-details
  CONTAINER_COUNT=0
  for ((i = 0; i < 30; i++)); do
    CONTAINER_COUNT=$(sudo docker ps -q 2>/dev/null | wc -l || true)
    [ "$CONTAINER_COUNT" -eq 1 ] && break
    sleep 1
  done
  if [ "$CONTAINER_COUNT" -ne 1 ]; then
    echo "Expected 1 running container, found $CONTAINER_COUNT"
    sudo docker ps -a
    exit 1
  fi

  # "Running" is not enough: with --restart=always a container whose GPU workload
  # keeps failing (e.g. a broken GPU after a refresh) crash-loops but still shows
  # as up. Assert the restart count is stable over a short window, so a
  # crash-looping container fails the test instead of silently passing.
  CONTAINER=$(sudo docker ps -q)
  RESTARTS_BEFORE=$(sudo docker inspect -f '{{.RestartCount}}' "$CONTAINER")
  sleep 5
  RESTARTS_AFTER=$(sudo docker inspect -f '{{.RestartCount}}' "$CONTAINER")
  if [ "$RESTARTS_AFTER" -gt "$RESTARTS_BEFORE" ]; then
    echo "Container is crash-looping (restart count $RESTARTS_BEFORE -> $RESTARTS_AFTER); GPU workload is failing"
    sudo docker logs "$CONTAINER" 2>&1 | tail -n 20
    exit 1
  fi
)

run_workload() (
  set -x
  sudo docker run --restart=always --detach -v "$(pwd)/run-vector.sh:/run-vector.sh:ro" --entrypoint=/run-vector.sh --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda10.2
)

main() {
  cleanup

  setup

  run_workload

  check_container

  refresh_docker "$1"

  check_container

  revert_docker

  check_container

  echo "Docker snap successfully refreshed and container is still running."
}

main "$1"
