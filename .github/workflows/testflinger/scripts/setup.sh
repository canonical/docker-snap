#!/usr/bin/env bash
set -e

run_retry_command() {
  local RETRIES=3
  local DELAY=5
  local n=1
  until "$@"; do
    if [[ $n -ge $RETRIES ]]; then
      echo "Command failed after $RETRIES attempts: $*"
      return 1
    fi
    echo "Command failed (attempt $n/$RETRIES): $*. Retrying in $DELAY seconds..."
    ((n++))
    sleep $DELAY
  done
}

apt_update() {
  # ignore errors, some nodes fail to access the repos
  set +e
  run_retry_command sudo apt-get -qq update
  set -e
}

install_snap() {
  SNAP_NAME=$1
  SNAP_CHANNEL=$2

  if snap list | grep -q "^$SNAP_NAME "; then
    echo "Snap $SNAP_NAME is already installed. Refreshing instead."
    if [[ -z "$SNAP_CHANNEL" ]]; then
      run_retry_command sudo snap refresh "$SNAP_NAME"
    else
      run_retry_command sudo snap refresh "$SNAP_NAME" --channel="$SNAP_CHANNEL"
    fi
  else
    echo "Installing $SNAP_NAME..."
    if [[ -z "$SNAP_CHANNEL" ]]; then
      run_retry_command sudo snap install "$SNAP_NAME"
    else
      run_retry_command sudo snap install "$SNAP_NAME" --channel="$SNAP_CHANNEL"
    fi
  fi
}

# parameter 1 is snap name, followed by components
install_components() {
  PARENT_SNAP=$1
  COMPONENTS=$2

  for COMPONENT_NAME in $COMPONENTS; do
    FULL_NAME="${PARENT_SNAP}+${COMPONENT_NAME}"

    if snap components "$PARENT_SNAP" 2>/dev/null | grep -q "$COMPONENT_NAME.*installed"; then
      echo "Component $COMPONENT_NAME is already installed."
    else
      echo "Installing $COMPONENT_NAME..."
      run_retry_command sudo snap install "$FULL_NAME"
    fi
  done
}

install_docker() (
  DOCKER_SNAP_CHANNEL=$1
  if [[ -z "$DOCKER_SNAP_CHANNEL" ]]; then
    DOCKER_SNAP_CHANNEL="latest/edge"
  fi

  set -x

  install_snap docker "$DOCKER_SNAP_CHANNEL"

  # check the auto-connections
  sudo snap connections docker
)

setup_classic() (
  set -x

  apt_update
  run_retry_command sudo apt-get -qqy install nvidia-driver-570
)

setup_core22() (
  set -x
  install_snap nvidia-core22
  install_snap nvidia-assemble 22/stable
)

setup_core24() (
  set -x
  # List available kernel components for debugging
  snap components pc-kernel

  # Install kernel components.
  PARENT_SNAP="pc-kernel"
  COMPONENTS="nvidia-550-erd-ko nvidia-550-erd-user"
  install_components $PARENT_SNAP "$COMPONENTS"

  install_snap mesa-2404
)

install_dependencies() {
  # Source variables that define the version.
  # e.g. core: ID=ubuntu-core, VERSION_ID="24"
  # e.g. desktop: ID=ubuntu, VERSION_ID="25.10"
  source /etc/os-release

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
install_docker "$1"

echo "A reboot is required!"
