#!/usr/bin/env bash
set -e

# Test nvidia-smi
smi_test() (
  . /etc/os-release

  set -x

  case "$ID-$VERSION_ID" in
    ubuntu-24.04)
      sudo docker run --rm --runtime=nvidia --gpus all --env PATH="${PATH}:/var/lib/snapd/hostfs/usr/bin" ubuntu nvidia-smi || true
      ;;
    ubuntu-core-22)
      sudo docker run --rm --runtime nvidia --gpus all ubuntu bash -c "/snap/docker/*/graphics/bin/nvidia-smi" || true
      ;;
    ubuntu-core-24)
      # Run nvidia-smi from the kernel snap
      LD_LIBRARY_PATH=/var/snap/pc-kernel/common/kernel-gpu-2404/usr/lib/x86_64-linux-gnu/ /var/snap/pc-kernel/common/kernel-gpu-2404/usr/bin/nvidia-smi || true
      ;;
    *)
      echo "Unsupported OS / version: $ID $VERSION_ID"
      exit 1
      ;;
  esac
)

# Test a vector addition sample workload
vector_add_test() (
  set -x
  sudo docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda10.2
)

print_logs() (
  set -x
  sudo snap logs -n 100 docker.nvidia-container-toolkit
)

print_logs

smi_test

vector_add_test
