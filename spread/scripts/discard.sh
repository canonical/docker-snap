#!/bin/bash
# Sourced by the garden backend discard hook in spread.yaml.
set -eu

# Spread automatically injects /snap/bin to PATH. When we are
# running from the image-garden snap then SPREAD_HOST_PATH is the
# original path before such modifications were applied. Snap
# applications cannot normally run /snap/bin/* entry-points
# successfully so re-set PATH to the original value, as provided by
# snapcraft.
if [ -n "${SPREAD_HOST_PATH-}" ]; then
  PATH="${SPREAD_HOST_PATH}"
fi

image-garden discard "$SPREAD_SYSTEM_ADDRESS"
