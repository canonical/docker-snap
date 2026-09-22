#!/usr/bin/env bats
# Tests for snap/hooks/configure run as a whole, with snapctl, dockerd and the nvidia
# lib faked (see daemon-config-fixture.bash). Service operations are asserted through
# the fake snapctl's log.

load daemon-config-fixture

setup() {
  _setup_snap_tree
  HOOK="$REPO/snap/hooks/configure"
}

teardown() {
  _teardown_snap_tree
}

_ops() { cat "$SNAPCTL_LOG" 2>/dev/null || true; }

@test "applies snap config, restarts the snap, logs the run and drops the snapshot" {
  _snap_config '{"mtu":1400}'
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_ops)" = $'stop docker\nstart docker' ]
  [ -f "$SNAP_COMMON/hooks/x1/configure.log" ]
  [ ! -e "$SNAP_DATA/.configure-rollback" ]
}

@test "only bounces the nvidia oneshot when nothing changed" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ "$(_ops)" = $'stop docker.nvidia-container-toolkit\nstart docker.nvidia-container-toolkit' ]
}

@test "fills in the data-root default when it is unset" {
  printf '{"daemon":{}}\n' > "$SNAPCTL_CONFIG"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(jq -r '."data-root"' "$SNAPCTL_CONFIG")" = /var/snap/docker/common/var-lib-docker ]
}

@test "re-seeds a missing daemon.json from the shipped default" {
  rm "$SNAP_DATA/config/daemon.json"
  _snap_config '{"mtu":1400}'
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
}

@test "fails on a disallowed option before touching anything, still logging the run" {
  _snap_config '{"hosts":["tcp://0.0.0.0:2375"]}'
  run bash "$HOOK"
  [ "$status" -ne 0 ]
  grep -qF "not configurable via snap: hosts" <<<"$output"
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
  [ -z "$(_ops)" ]
  [ -f "$SNAP_COMMON/hooks/x1/configure.log" ]
}

@test "fails without touching anything when snapctl cannot read the options" {
  _snap_config '{"mtu":1400}'
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  local before
  before="$(_file)"
  : > "$SNAPCTL_LOG"
  _snap_config '{"mtu":1450}'
  SNAPCTL_FAIL="get daemon" run bash "$HOOK"
  [ "$status" -ne 0 ]
  [ "$(_file)" = "$before" ]
  [ "$(_keys)" = '["mtu"]' ]
  [ -z "$(_ops)" ]
}

@test "rolls the file and key list back when the restart fails" {
  _snap_config '{"mtu":1400}'
  SNAPCTL_FAIL="start docker" run bash "$HOOK"
  [ "$status" -ne 0 ]
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
  [ ! -e "$SNAP_DATA/.configure-rollback" ]
  [ "$(_ops)" = $'stop docker\nstart docker' ]
}

@test "rolls the key list back without a restart when only the key list moved" {
  _hand '. + {"mtu":1400}'
  _snap_config '{"mtu":1400}'
  SNAPCTL_FAIL="start docker.nvidia-container-toolkit" run bash "$HOOK"
  [ "$status" -ne 0 ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_ops)" = $'stop docker.nvidia-container-toolkit\nstart docker.nvidia-container-toolkit' ]
}

@test "leaves services alone when the hook fails before stopping them" {
  _snap_config '{"mtu":1400}'
  # a directory in the way makes the nvidia branch's write fail after the merge
  mkdir "$SNAP_DATA/config/daemon.json.new"
  NVIDIA_DISABLED=1 run bash "$HOOK"
  [ "$status" -ne 0 ]
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ -z "$(_ops)" ]
}

@test "removes the nvidia runtime entry when nvidia support is disabled" {
  _hand '. + {"runtimes":{"nvidia":{"path":"nvidia-container-runtime"}}}'
  NVIDIA_DISABLED=1 run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(_file)" = '{"log-level":"error","runtimes":{}}' ]
  [ "$(_ops)" = $'stop docker\nstart docker' ]
}

@test "rolls the nvidia runtime deletion back when the restart fails" {
  _hand '. + {"runtimes":{"nvidia":{"path":"nvidia-container-runtime"}}}'
  SNAPCTL_FAIL="start docker" NVIDIA_DISABLED=1 run bash "$HOOK"
  [ "$status" -ne 0 ]
  # pin: a restart failure after the nvidia branch restores the nvidia entry too
  [ "$(_file)" = '{"log-level":"error","runtimes":{"nvidia":{"path":"nvidia-container-runtime"}}}' ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
  [ ! -e "$SNAP_DATA/.configure-rollback" ]
  [ "$(_ops)" = $'stop docker\nstart docker' ]
}

@test "a snap-set option survives a refresh and then follows the new default" {
  _snap_config '{"log-level":"info"}'
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  _refresh_to_new_revision
  printf '{"log-level":"warn"}\n' > "$SNAP/config/daemon.json"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(_file)" = '{"log-level":"info"}' ]
  [ "$(_keys)" = '["log-level"]' ]
  _snap_config '{}'
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(_file)" = '{"log-level":"warn"}' ]
}

@test "an option set before the feature existed is applied on the next revision" {
  # nothing applied it on the old revision, so there is no key list to carry over
  _snap_config '{"mtu":1400}'
  _refresh_to_new_revision
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
}

@test "a key dropped from the allowlist blocks the hook after a refresh" {
  _snap_config '{"mtu":1400}'
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  _refresh_to_new_revision
  grep -v '^    mtu$' "$SNAP/lib/daemon-config" > "$T/lib" && mv "$T/lib" "$SNAP/lib/daemon-config"
  run bash "$HOOK"
  # pin: retiring a key while it is still set breaks the refresh, which is why removing one
  # needs the stored value unset first
  [ "$status" -ne 0 ]
  grep -qF "not configurable via snap: mtu" <<<"$output"
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
}
