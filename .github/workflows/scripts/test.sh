#!/usr/bin/env bash
set -ex

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

smi_test

vector_add_test
