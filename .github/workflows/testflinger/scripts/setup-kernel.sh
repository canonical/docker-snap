#!/usr/bin/env bash
set -e

core24() {
  set -x
  sudo snap refresh pc-kernel --channel=24/edge/nvidia-components-sdp
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

echo "A reboot is required!"
