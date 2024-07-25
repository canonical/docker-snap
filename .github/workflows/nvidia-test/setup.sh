#!/usr/bin/env bash
set -ex

install_docker() {
  # install docker-snap
  # sudo snap install ${{ steps.snapcraft.outputs.docker.snap }} --dangerous
  sudo snap install docker --edge

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
  sudo apt-get update && sudo apt-get install -y curl

  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb
  sudo apt-get update
  sudo apt-get -y install cuda-toolkit-12-5

  sudo apt-get install -y nvidia-driver-555-open
  sudo apt-get install -y cuda-drivers-555

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  sudo apt-get update
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