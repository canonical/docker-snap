#!/usr/bin/env bash
set -e

apt_update() {
  # ignore errors, some nodes fail to access the repos
  set +e
  sudo apt-get -qq update
  set -e
}

install_docker() (
  # SNAP_CHANNEL may be set by the caller, or replaced in CI
  DOCKER_SNAP_CHANNEL=$SNAP_CHANNEL
  if [[ -z "$DOCKER_SNAP_CHANNEL" ]]; then
    DOCKER_SNAP_CHANNEL="latest/edge"
  fi

  set -x

  # install docker-snap
  sudo snap install docker --channel="$DOCKER_SNAP_CHANNEL"

  # check the auto-connections
  sudo snap connections docker
)

setup_classic() (

  set -x

  apt_update
  sudo apt-get -qqy install nvidia-driver-580
)

setup_core22() (
  set -x
  sudo snap install nvidia-core22
  sudo snap install nvidia-assemble --channel 22/stable
)

setup_core24() (
  set -x
  snap components pc-kernel

  # Install kernel components. 
  sudo snap install pc-kernel+nvidia-580-erd-ko
  sudo snap install pc-kernel+nvidia-580-erd-user
  
  sudo snap install mesa-2404
)

install_dependencies() {
  . /etc/os-release

  case "$ID-$VERSION_ID" in
    ubuntu-24.04)
      setup_classic
      ;;
    ubuntu-core-22)
      setup_core22
      ;;
    ubuntu-core-24)
      setup_core24
      ;;
    *)
      echo "Unsupported OS / version: $ID $VERSION_ID"
      exit 1
      ;;
  esac
}

install_dependencies
install_docker

echo "A reboot is required!"
