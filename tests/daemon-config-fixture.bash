# Shared fixture for the daemon-config tests: a throwaway snap tree with the lib
# installed, a fake dockerd that only knows --validate, a fake snapctl on PATH
# backed by a JSON document, and the nvidia lib reduced to what the hook uses.
# Load with `load daemon-config-fixture`.

REPO="$BATS_TEST_DIRNAME/.."

_setup_snap_tree() {
  T="$(mktemp -d)"
  export SNAP="$T/snap" SNAP_DATA="$T/data" SNAP_COMMON="$T/common"
  export SNAP_NAME=docker SNAP_REVISION=x1
  export SNAPCTL_CONFIG="$T/snapctl.json" SNAPCTL_LOG="$T/snapctl.log"
  mkdir -p "$SNAP/config" "$SNAP/bin" "$SNAP/usr/share/docker" \
    "$SNAP/usr/share/nvidia-container-toolkit" "$SNAP_DATA/config" "$SNAP_COMMON" "$T/bin"
  printf '{"log-level":"error"}\n' > "$SNAP/config/daemon.json"
  cp "$SNAP/config/daemon.json" "$SNAP_DATA/config/daemon.json"
  cp "$REPO/lib/daemon-config" "$SNAP/usr/share/docker/daemon-config"
  _install_fake_dockerd
  _install_fake_snapctl
  _install_fake_nvidia_lib
  PATH="$T/bin:$PATH"
  _snap_config '{}'
}

_teardown_snap_tree() {
  rm -rf "$T"
}

# Only `--validate --config-file=<path>`. Rejects a file carrying the key "bad" (an
# unknown directive) or an mtu of 13 (a bad value), the way dockerd would.
_install_fake_dockerd() {
  cat > "$SNAP/bin/dockerd" <<'DOCKERD'
#!/usr/bin/env bash
for arg; do
  case "$arg" in (--config-file=*) f="${arg#--config-file=}" ;; esac
done
if ! jq -e 'type == "object" and (has("bad") | not) and .mtu != 13' "$f" >/dev/null 2>&1; then
  printf "unable to configure the Docker daemon with file %s: the following directives don't match any configuration option: bad\n" "$f" >&2
  exit 1
fi
printf 'configuration OK\n'
DOCKERD
  chmod +x "$SNAP/bin/dockerd"
}

# Backed by $SNAPCTL_CONFIG; service operations are appended to $SNAPCTL_LOG.
# SNAPCTL_FAIL="start docker" makes exactly that operation fail.
_install_fake_snapctl() {
  cat > "$T/bin/snapctl" <<'SNAPCTL'
#!/usr/bin/env bash
case "$1" in
  (get)
    if [ "$2" = "-d" ]; then
      jq -c --arg k "$3" '{($k): .[$k]}' "$SNAPCTL_CONFIG"
    else
      jq -r --arg k "$2" '.[$k] // empty' "$SNAPCTL_CONFIG"
    fi ;;
  (set)
    shift
    for kv; do
      jq --arg k "${kv%%=*}" --arg v "${kv#*=}" '.[$k] = $v' "$SNAPCTL_CONFIG" > "$SNAPCTL_CONFIG.new" \
        && mv "$SNAPCTL_CONFIG.new" "$SNAPCTL_CONFIG"
    done ;;
  (stop|start|restart)
    printf '%s %s\n' "$1" "$2" >> "$SNAPCTL_LOG"
    [ "$1 $2" != "${SNAPCTL_FAIL:-}" ] || exit 1 ;;
  (*)
    printf 'fake snapctl: unsupported: %s\n' "$*" >&2
    exit 2 ;;
esac
SNAPCTL
  chmod +x "$T/bin/snapctl"
}

_install_fake_nvidia_lib() {
  cat > "$SNAP/usr/share/nvidia-container-toolkit/lib" <<'NVIDIA'
DEFAULT_DATA_ROOT=/var/snap/docker/common/var-lib-docker
nvidia_support_disabled() { [ "${NVIDIA_DISABLED:-}" = 1 ]; }
NVIDIA
}

# _snap_config <json>: the `daemon` subtree snapctl will report.
_snap_config() {
  printf '{"data-root":"/var/snap/docker/common/var-lib-docker","daemon":%s}\n' "$1" > "$SNAPCTL_CONFIG"
}

# _hand <jq filter>: edit daemon.json the way a user would.
_hand() {
  jq "$1" "$SNAP_DATA/config/daemon.json" > "$SNAP_DATA/config/daemon.json.edit" \
    && mv "$SNAP_DATA/config/daemon.json.edit" "$SNAP_DATA/config/daemon.json"
}

_file() { jq -c -S . "$SNAP_DATA/config/daemon.json"; }
_keys() { cat "$SNAP_DATA/daemon-config-keys"; }
