#!/usr/bin/env bash
set -e

# A zero exit from nvidia-smi is not enough: a degenerate success with no GPU
# visible would still pass. Assert the output carries the real driver banner.
assert_driver() {
  echo "$1"
  echo "$1" | grep -q "Driver Version"
}

# Test nvidia-smi
smi_test() (
  # shellcheck disable=SC1091  # /etc/os-release is provided by the OS at runtime
  source /etc/os-release

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
    ubuntu-core-26)
      # In a container, via the nvidia-smi the toolkit mounts from the docker
      # snap's gpu-2604 component (provided by mesa-2604).
      smi_out=$(sudo docker run --rm --runtime=nvidia --gpus all ubuntu bash -c "/snap/docker/*/gpu-2604*/usr/bin/nvidia-smi")
      assert_driver "$smi_out"
      # And on the host, from the kernel snap. nvidia-active points at the
      # active nvidia component.
      smi_out=$(LD_LIBRARY_PATH=/var/snap/pc-kernel/common/nvidia-active/usr/lib/x86_64-linux-gnu/ /var/snap/pc-kernel/common/nvidia-active/usr/bin/nvidia-smi)
      assert_driver "$smi_out"
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
  sudo docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda11.7.1
  sudo docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0
)

print_logs() (
  set -x
  sudo snap logs -n 100 docker.nvidia-container-toolkit
)

print_logs

smi_test

vector_add_test
