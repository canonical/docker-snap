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
  run_retry_command sudo apt-get -qqy install nvidia-driver-580
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
  COMPONENTS="nvidia-580-erd-ko nvidia-580-erd-user"
  install_components $PARENT_SNAP "$COMPONENTS"

  install_snap mesa-2404
)

# On core26 the nvidia userspace reaches the docker snap through a chain:
# pc-kernel (nvidia -user component) -> mesa-2604's kernel-gpu-2604 content
# plug -> mesa-2604's component-monitor mangles it into $SNAP_DATA -> exposed
# through the gpu-2604 slot -> docker's gpu-2604 plug. The docker<->mesa link
# auto-connects, but the mesa<->pc-kernel one has been observed dangling, which
# leaves the container toolkit without NVIDIA_DRIVER_ROOT and breaks CDI spec
# generation. Connect it explicitly and wait for the mangled content to land.
connect_kernel_gpu_2604() {
  # Show both ends of the chain for debugging before touching anything
  snap connections mesa-2604 || true
  snap connections pc-kernel | grep -i gpu || true

  if ! snap connections mesa-2604 | grep -qE "mesa-2604:kernel-gpu-2604 +pc-kernel:"; then
    echo "Connecting mesa-2604:kernel-gpu-2604 to pc-kernel"
    run_retry_command sudo snap connect mesa-2604:kernel-gpu-2604 pc-kernel:kernel-gpu-2604
  fi

  # mesa-2604's component-monitor watches the plug content via inotify and
  # populates $SNAP_DATA/kernel-gpu-2604, writing the sentinel file last.
  for ((i = 0; i < 30; i++)); do
    if sudo test -e /var/snap/mesa-2604/current/kernel-gpu-2604/kernel-gpu-2604-sentinel; then
      echo "kernel-gpu-2604 content mangled and ready"
      return 0
    fi
    sleep 2
  done

  echo "kernel-gpu-2604 content did not appear; the toolkit would run without the nvidia userspace."
  echo "Chain state for debugging:"
  snap connections mesa-2604 || true
  sudo ls -la /var/snap/mesa-2604/current/kernel-gpu-2604/ || true
  return 1
}

setup_core26() (
  set -x
  # List available kernel components for debugging
  snap components pc-kernel

  # Install kernel components.
  PARENT_SNAP="pc-kernel"
  COMPONENTS="nvidia-580-erd-ko nvidia-580-erd-user"
  install_components $PARENT_SNAP "$COMPONENTS"

  install_snap mesa-2604

  connect_kernel_gpu_2604
)

install_dependencies() {
  # Source variables that define the version.
  # e.g. core: ID=ubuntu-core, VERSION_ID="24"
  # e.g. desktop: ID=ubuntu, VERSION_ID="25.10"
  # shellcheck disable=SC1091  # /etc/os-release is provided by the OS at runtime
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
  ubuntu-core-26)
    setup_core26
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
