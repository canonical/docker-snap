#!/bin/bash

set -eux

# yq preserving blank lines
yq_p() {
  yq "$1" "$2" | diff -wB "$2" - | patch "$2" -
}

fetch_latest() {
  # Fetch latest version from Github releases API
  LATEST=$(curl -s "https://api.github.com/repos/moby/moby/releases?per_page=1" | jq -r '.[0].tag_name')
}

# Validate the version format
validate_version() {
  # Original simplified RegEx:
  # v\d+.\d+.\d+\-*(rc.\d|rc\d|beta.\d)*
  # By analysing the last tags on github.com/moby/moby/tags
  # of last 3 years (since 2021).
  if [[ "$LATEST" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]|rc[0-9]|beta\.[0-9])?$ ]]; then
    echo "$LATEST matches the regex."
  else
    echo "Version doesn't match known pattern."
    exit 1
  fi
}

check_yq() {
  if ! command -v yq &>/dev/null; then
    echo -e "yq is not installed."
    echo -e "Please run:"
    echo -e "\tsudo snap install yq"
    exit 1
  fi
}

check_new_version() {
  if [[ "$CURRENT" == "$LATEST" ]]; then
    echo -e "Docker snap is already updated\n"
    exit 0
  fi
}

main() {
  check_yq

  # Define the path to the YAML file
  yaml_file="snap/snapcraft.yaml"

  CURRENT=$(yq e '.parts.engine.source-tag' "$yaml_file")

  fetch_latest

  echo "Latest TAG: $LATEST"

  validate_version

  check_new_version

  SNAP_VERSION=${LATEST#v}
  echo -e "New snap version $SNAP_VERSION"

  echo "The latest version of moby is: $LATEST"

  # Fetch the Dockerfile
  dockerfile=$(curl -s "https://raw.githubusercontent.com/moby/moby/refs/tags/$LATEST/Dockerfile")

  # Declare variables and their corresponding regex patterns
  declare -A variables=(
    [GO_VERSION]='^ARG GO_VERSION='
    [CONTAINERD_VERSION]='^ARG CONTAINERD_VERSION='
    [RUNC_VERSION]='^ARG RUNC_VERSION='
    [TINI_VERSION]='^ARG TINI_VERSION='
    [DOCKERCLI_VERSION]='^ARG DOCKERCLI_VERSION='
    [BUILDX_VERSION]='^ARG BUILDX_VERSION='
    [COMPOSE_VERSION]='^ARG COMPOSE_VERSION='
  )

  # Extract versions using a loop
  for var in "${!variables[@]}"; do
    value=$(echo "$dockerfile" | awk -F= "/${variables[$var]}/ {print \$2}")

    # Handle special cases: GO_VERSION and BUILDX_VERSION
    if [[ "$var" == "GO_VERSION" ]]; then
      # for GO_VERSION Extract major.minor
      value=$(echo "$value" | awk -F. '{print $1 "." $2}')
    elif [[ "$var" == "BUILDX_VERSION" && $value != v* ]]; then
      value="v$value" # Prepend 'v' if missing
    fi

    declare "$var=$value"
    echo "$var: ${!var}"
  done

  # Replace the `version:` field with the value of $SNAP_VERSION
  yq_p ".version = \"$SNAP_VERSION\"" "$yaml_file"

  # Replace fields in YAML using a loop
  declare -A yaml_updates=(
    [engine.source-tag]=$LATEST
    [containerd.source-tag]=$CONTAINERD_VERSION
    [runc.source-tag]=$RUNC_VERSION
    [tini.source-tag]=$TINI_VERSION
    [docker-cli.source-tag]=$DOCKERCLI_VERSION
    [buildx.source-tag]=$BUILDX_VERSION
    [compose-v2.source-tag]=$COMPOSE_VERSION
  )

  for part in "${!yaml_updates[@]}"; do
    yq_p ".parts.${part} = \"${yaml_updates[$part]}\"" "$yaml_file"
  done

  # Replace `build-snaps` for `engine` with $GO_VERSION
  yq_p '.parts.engine."build-snaps"[0] |= sub("[0-9]+\.[0-9]+", "'"$GO_VERSION"'")' "$yaml_file"

  # Replace the remaining comments
  sed -i "s/moby\/blob\/$CURRENT/moby\/blob\/$LATEST/g" "$yaml_file"

  echo "YAML file updated successfully."

}

main
