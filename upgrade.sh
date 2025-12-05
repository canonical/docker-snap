#!/bin/bash

set -eu

VM_NAME=docker-upgrader

# yq preserving blank lines
yq_p() {
  yq "$1" "$2" | diff -wB "$2" - | patch "$2" -
}

check_yq() {
  if ! command -v yq &>/dev/null; then
    echo -e "yq is not installed."
    echo -e "Please run:"
    echo -e "\tsudo snap install yq"
    exit 1
  fi
}

check_multipass() {
  if ! command -v multipass &>/dev/null; then
    echo -e "multipass is not installed."
    echo -e "Please install multipass first."
    exit 1
  fi
}

launch_vm() {
  echo "Launching Multipass VM..."
  multipass launch noble -n "${VM_NAME}" -c 2 -m 4G -d 10G || {
    echo "VM might already exist, trying to start it..."
    multipass start docker-upgrader || true
  }

  # Wait for VM to be ready
  sleep 5
}

install_docker() {
  echo "Installing Docker Engine in VM..."

  # Install prerequisites
  multipass exec "${VM_NAME}" -- sudo apt-get update
  multipass exec "${VM_NAME}" -- sudo apt-get install -y ca-certificates curl

  # Add Docker's official GPG key
  multipass exec "${VM_NAME}" -- sudo install -m 0755 -d /etc/apt/keyrings
  multipass exec "${VM_NAME}" -- sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  multipass exec "${VM_NAME}" -- sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources
  multipass exec "${VM_NAME}" -- bash -c 'sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF'

  # Install Docker
  multipass exec "${VM_NAME}" -- sudo apt-get update
  multipass exec "${VM_NAME}" -- sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  echo "Docker installation complete."
}

extract_versions() {
  echo "Extracting version information..."

  # Get docker version output in JSON format
  docker_version=$(multipass exec "${VM_NAME}" -- sudo docker version --format json)

  # Extract versions using yq with JSON parser
  ENGINE_VERSION=$(echo "$docker_version" | yq -p=json '.Server.Version')
  DOCKERCLI_VERSION=$(echo "$docker_version" | yq -p=json '.Client.Version')
  GO_VERSION=$(echo "$docker_version" | yq -p=json '.Server.GoVersion' | sed 's/go//')
  CONTAINERD_VERSION=$(echo "$docker_version" | yq -p=json '.Server.Components[] | select(.Name == "containerd") | .Version')
  RUNC_VERSION=$(echo "$docker_version" | yq -p=json '.Server.Components[] | select(.Name == "runc") | .Version')
  TINI_VERSION=$(echo "$docker_version" | yq -p=json '.Server.Components[] | select(.Name == "docker-init") | .Version')

  # Get buildx version (doesn't support --format json)
  buildx_version=$(multipass exec "${VM_NAME}" -- sudo docker buildx version)
  BUILDX_VERSION=$(echo "$buildx_version" | awk '{print $2}')

  # Get compose version in JSON format
  compose_version=$(multipass exec "${VM_NAME}" -- sudo docker compose version --format json)
  COMPOSE_VERSION=$(echo "$compose_version" | yq -p=json '.version')

  # Extract major.minor for Go version
  GO_VERSION=$(echo "$GO_VERSION" | awk -F. '{print $1 "." $2}')

  # Ensure versions have 'v' prefix where needed
  [[ "$DOCKERCLI_VERSION" != v* ]] && DOCKERCLI_VERSION="v$DOCKERCLI_VERSION"
  [[ "$CONTAINERD_VERSION" != v* ]] && CONTAINERD_VERSION="v$CONTAINERD_VERSION"
  [[ "$RUNC_VERSION" != v* ]] && RUNC_VERSION="v$RUNC_VERSION"
  [[ "$BUILDX_VERSION" != v* ]] && BUILDX_VERSION="v$BUILDX_VERSION"
  [[ "$COMPOSE_VERSION" != v* ]] && COMPOSE_VERSION="v$COMPOSE_VERSION"
  [[ "$TINI_VERSION" != v* ]] && TINI_VERSION="v$TINI_VERSION"

  # Construct ENGINE_TAG (format: docker-v{version})
  ENGINE_TAG="docker-v$ENGINE_VERSION"

  echo "Extracted versions:"
  echo "  ENGINE_TAG: $ENGINE_TAG"
  echo "  DOCKERCLI_VERSION: $DOCKERCLI_VERSION"
  echo "  GO_VERSION: $GO_VERSION"
  echo "  CONTAINERD_VERSION: $CONTAINERD_VERSION"
  echo "  RUNC_VERSION: $RUNC_VERSION"
  echo "  TINI_VERSION: $TINI_VERSION"
  echo "  BUILDX_VERSION: $BUILDX_VERSION"
  echo "  COMPOSE_VERSION: $COMPOSE_VERSION"
}

check_new_version() {
  yaml_file="snap/snapcraft.yaml"
  CURRENT=$(yq e '.parts.engine.source-tag' "$yaml_file")

  if [[ "$CURRENT" == "$ENGINE_TAG" ]]; then
    echo -e "Docker snap is already updated\n"
    cleanup_vm
    exit 0
  fi
}

update_yaml() {
  yaml_file="snap/snapcraft.yaml"

  echo "Updating snapcraft.yaml..."

  # Get current version for sed replacement
  CURRENT=$(yq e '.parts.engine.source-tag' "$yaml_file")

  # Update snap version (remove 'v' prefix)
  SNAP_VERSION=${ENGINE_VERSION}
  echo "New snap version: $SNAP_VERSION"

  yq_p ".version = \"$SNAP_VERSION\"" "$yaml_file"

  # Replace fields in YAML using a loop
  declare -A yaml_updates=(
    ["engine.source-tag"]=$ENGINE_TAG
    ["containerd.source-tag"]=$CONTAINERD_VERSION
    ["runc.source-tag"]=$RUNC_VERSION
    ["tini.source-tag"]=$TINI_VERSION
    ["docker-cli.source-tag"]=$DOCKERCLI_VERSION
    ["buildx.source-tag"]=$BUILDX_VERSION
    ["compose-v2.source-tag"]=$COMPOSE_VERSION
  )

  for part in "${!yaml_updates[@]}"; do
    yq_p ".parts.${part} = \"${yaml_updates[$part]}\"" "$yaml_file"
  done

  # Replace `build-snaps` for `engine` with $GO_VERSION
  yq_p '.parts.engine."build-snaps"[0] |= sub("[0-9]+\.[0-9]+", "'"$GO_VERSION"'")' "$yaml_file"

  # Replace the remaining comments (update blob references)
  sed -i "s/moby\/blob\/$CURRENT/moby\/blob\/$ENGINE_TAG/g" "$yaml_file"

  echo "YAML file updated successfully."
}

cleanup_vm() {
  echo "Cleaning up VM..."
  multipass delete "${VM_NAME}"
  multipass purge
  echo "VM cleaned up."
}

main() {
  check_yq
  check_multipass

  launch_vm
  install_docker
  extract_versions
  check_new_version
  update_yaml
  cleanup_vm

  echo "Docker snap update complete!"
}

main
