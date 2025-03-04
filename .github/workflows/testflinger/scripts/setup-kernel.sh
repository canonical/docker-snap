#!/usr/bin/env bash
set -e

core24() {
  set -x
  sudo snap refresh pc-kernel --channel=24/edge/nvidia-components
  set +x

  echo "Rebooting the device after a few seconds ..."
  # Reboot the device in the background to avoid breaking the SSH connection prematurely
  (sleep 3 && sudo reboot) &
}

install_kernel() {
  . /etc/os-release

  case "$ID-$VERSION_ID" in
    ubuntu-core-24)
      core24
      ;;
    *)
      echo "No operations for: $ID $VERSION_ID"
      ;;
  esac
}

install_kernel
