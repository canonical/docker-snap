#!/usr/bin/env bash
set -x

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

classic_setup() {
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

core_setup() {
  sudo snap install nvidia-core22
  sudo snap install nvidia-assemble --channel 22/stable
}

setup() {
  . /etc/os-release

  if [ ! -f $HOME/setup-done ]; then
    install_docker

    if [[ $ID == "ubuntu" ]]; then
      classic_setup

    elif [[ $ID == "ubuntu-core" ]]; then
      core_setup

    else
      echo "Invalid system type"
      exit 1
    fi

    # Since the reboot is necessary
    touch $HOME/setup-done

    sudo reboot now
  fi
}

# Test nvidia-smi
smi_test() {

  if [[ $ID == "ubuntu" ]]; then

    sudo docker run --rm --runtime=nvidia --gpus all --env PATH="${PATH}:/var/lib/snapd/hostfs/usr/bin" ubuntu nvidia-smi || exit 1
  elif [[ $ID == "ubuntu-core" ]]; then
    sudo docker run --rm --runtime nvidia --gpus all -it ubuntu bash -c "/snap/docker/*/graphics/bin/nvidia-smi" || exit 1
  else
    echo "Invalid system type"
    exit 1
  fi
}

# Test a vector addition sample workload
vector_add_test() {
  sudo docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda10.2 || exit 1
}

setup

smi_test

vector_add_test
