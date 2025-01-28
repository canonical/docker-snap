#!/usr/bin/env bash
set -e

apt_update() {
  # ignore errors, some nodes fail to access the repos
  set +e
  sudo apt -qq update
  set -e
}

install_docker() {
  # SNAP_CHANNEL may be set by the caller, or replaced in CI
  DOCKER_SNAP_CHANNEL=$SNAP_CHANNEL
  if [[ -z "$DOCKER_SNAP_CHANNEL" ]]; then
    DOCKER_SNAP_CHANNEL="latest/edge"
  fi

  # install docker-snap
  sudo snap install docker --channel="$DOCKER_SNAP_CHANNEL"

  # check the auto-connections
  sudo snap connections docker
}

setup_classic() {
  . /etc/os-release
  UBUNTU_VERSION="${VERSION_ID//./}"

  apt_update
  sudo apt-get install -y curl

  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$UBUNTU_VERSION/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb

  apt_update
  sudo apt -qqy install cuda-toolkit-12-8
  sudo apt -qqy install nvidia-driver-555-open
  sudo apt -qqy install cuda-drivers-555

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  apt_update
  sudo apt -qqy install nvidia-container-toolkit
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

# Don't refresh while testing
sudo snap refresh --hold=3h

set -x
setup
set +x

echo "A reboot is required!"
