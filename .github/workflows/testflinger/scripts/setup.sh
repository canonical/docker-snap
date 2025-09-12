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
  . /etc/os-release
  UBUNTU_VERSION="${VERSION_ID//./}"

  set -x

  apt_update
  sudo apt-get -qqy install -y curl

  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$UBUNTU_VERSION/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb

  apt_update
  sudo apt-get -qqy install cuda-toolkit-12-8
  sudo apt-get -qqy install nvidia-driver-555-open
  sudo apt-get -qqy install cuda-drivers-555

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  apt_update
  sudo apt-get -qqy install nvidia-container-toolkit
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
  sudo snap install pc-kernel+nvidia-570-erd-ko
  sudo snap install pc-kernel+nvidia-570-erd-user
  
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
