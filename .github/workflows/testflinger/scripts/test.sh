#!/usr/bin/env bash
set -e

# Test nvidia-smi
smi_test() {
  . /etc/os-release
  
  if [[ $ID == "ubuntu" ]]; then
    sudo docker run --rm --runtime=nvidia --gpus all --env PATH="${PATH}:/var/lib/snapd/hostfs/usr/bin" ubuntu nvidia-smi || true
  elif [[ $ID == "ubuntu-core" ]]; then
    sudo docker run --rm --runtime nvidia --gpus all ubuntu bash -c "/snap/docker/*/graphics/bin/nvidia-smi" || true
  else
    echo "Unexpected operating system ID: $ID"
    exit 1
  fi
}

# Test a vector addition sample workload
vector_add_test() {
  sudo docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda10.2
}

set -x
sudo snap logs -n 100 docker.nvidia-container-toolkit

smi_test

vector_add_test
set +x
