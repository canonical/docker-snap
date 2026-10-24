#!/usr/bin/env bash
set -e

# A zero exit from nvidia-smi is not enough: a degenerate success with no GPU
# visible would still pass. Assert the output carries the real driver banner.
assert_driver() {
  echo "$1"
  echo "$1" | grep -q "Driver Version"
}

# Kernel, component and module state on Core 24, so a driver that does not
# come up can be read off the log instead of a reserved box.
core24_diag() (
  set -x
  uname -r
  snap list pc-kernel
  snap components pc-kernel
  cat /sys/module/nvidia/version || true
  lsmod | grep -i nvidia || true
  ls /var/snap/pc-kernel/*/modules/*/ /var/snap/pc-kernel/common/kernel-gpu-2404/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.* || true
  sudo dmesg | grep -iE 'nvidia|nvrm' | tail -n 20 || true
  sudo snap changes | tail -n 6 || true
)

# Test nvidia-smi in a container. The CDI spec is generated with the driver
# root stripped from container paths, so nvidia-smi is on the default PATH.
smi_test() (
  # shellcheck disable=SC1091  # /etc/os-release is provided by the OS at runtime
  source /etc/os-release

  set -x

  case "$ID-$VERSION_ID" in
    ubuntu-24.04)
      # Classic has to win over a connected content provider, whatever the
      # host's lib layout.
      sudo snap logs -n 100 docker.nvidia-container-toolkit | grep -q "Running on Classic system"
      ;;
    ubuntu-core-22)
      ;;
    ubuntu-core-24)
      core24_diag
      # On the host first, from the kernel snap: the container path mounts the
      # same GPU stack, so a broken kernel component fails here with a clearer
      # cause than it would inside a container.
      smi_out=$(LD_LIBRARY_PATH=/var/snap/pc-kernel/common/kernel-gpu-2404/usr/lib/x86_64-linux-gnu/ /var/snap/pc-kernel/common/kernel-gpu-2404/usr/bin/nvidia-smi)
      assert_driver "$smi_out"
      ;;
    *)
      echo "Unsupported OS / version: $ID $VERSION_ID"
      exit 1
      ;;
  esac

  smi_out=$(sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi)
  assert_driver "$smi_out"
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
