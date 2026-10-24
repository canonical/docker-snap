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

# Move the driver libs out of the multiarch dir into a flat /usr/lib, the Arch
# layout. The toolkit then has to find them through the host's ld cache rather
# than a Debian path. mesa-2404 mirrors the setup of the Arch report: with
# gpu-2404 connected, a missed classic check used to fall through to the Core
# path.
flatten_lib_layout() (
  set -x
  shopt -s nullglob

  cd /usr/lib/x86_64-linux-gnu
  sudo mv -t /usr/lib/ libcuda*.so* libnvidia-*.so* libnvcuvid.so* libnvoptix.so* \
    libEGL_nvidia.so* libGLX_nvidia.so* libGLESv*_nvidia.so*
  echo /usr/lib | sudo tee /etc/ld.so.conf.d/zz-flat-nvidia.conf
  sudo ldconfig
  ls -l /usr/lib/libcuda.so*

  install_snap mesa-2404
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

install_dependencies() {
  # Source variables that define the version.
  # e.g. core: ID=ubuntu-core, VERSION_ID="24"
  # e.g. desktop: ID=ubuntu, VERSION_ID="25.10"
  # shellcheck disable=SC1091  # /etc/os-release is provided by the OS at runtime
  source /etc/os-release

  case "$ID-$VERSION_ID" in
  ubuntu-24.04)
    setup_classic
    if [[ $LIB_LAYOUT == flat ]]; then
      flatten_lib_layout
    fi
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

# parameter 1 is the docker snap channel, parameter 2 the host lib layout on classic
LIB_LAYOUT="${2:-multiarch}"
case "$LIB_LAYOUT" in
multiarch | flat) ;;
*)
  echo "Unsupported lib layout: $LIB_LAYOUT"
  exit 1
  ;;
esac

install_dependencies
install_docker "$1"

echo "A reboot is required!"
