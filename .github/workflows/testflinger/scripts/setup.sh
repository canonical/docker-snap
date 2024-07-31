#!/usr/bin/env bash
set -ex

apt_update() {
  # This is necessary due some Testflinger machines fail on
  set +e
  sudo apt-get update
  set -e
}

install_docker() {
  # install docker-snap
  DOCKER_SNAP_CHANNEL=$SNAP_CHANNEL
  if [[ -z "$DOCKER_SNAP_CHANNEL" ]]; then
    DOCKER_SNAP_CHANNEL="latest/edge"
  fi
  sudo snap install docker --channel="$DOCKER_SNAP_CHANNEL"

  # Connecting needed interfaces (Not need now, but need when instaling from artifact)
  sudo snap connect docker:network-control :network-control
  sudo snap connect docker:firewall-control :firewall-control
  sudo snap connect docker:support :docker-support
  sudo snap connect docker:privileged :docker-support
  sudo snap connect docker:docker-cli docker:docker-daemon

  # Check installation
  docker --version || exit 1
}

setup_classic() {
  . /etc/os-release
  UBUNTU_VERSION="${VERSION_ID//./}"

  apt_update
  sudo apt-get install -y curl

  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$UBUNTU_VERSION/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb

  apt_update
  sudo apt-get -y install cuda-toolkit-12-5
  sudo apt-get install -y nvidia-driver-555-open
  sudo apt-get install -y cuda-drivers-555

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  apt_update
  sudo apt-get install -y nvidia-container-toolkit
}

setup_core() {
  sudo snap install nvidia-core22
  sudo snap install nvidia-assemble --channel 22/stable
}

setup() {
  . /etc/os-release

  install_docker

  if [[ $ID == "ubuntu" ]]; then
    setup_classic

  elif [[ $ID == "ubuntu-core" ]]; then
    setup_core

  else
    echo "Unexpected operating system ID: $ID"
    exit 1
  fi
}

setup

echo "A reboot is required!"
