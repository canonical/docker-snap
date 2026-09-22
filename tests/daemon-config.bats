#!/usr/bin/env bats
# Unit tests for lib/daemon-config: the lib is sourced into the test shell with the
# snap environment pointed at a temp tree (see daemon-config-fixture.bash).

load daemon-config-fixture

setup() {
  _setup_snap_tree
  # shellcheck disable=SC1091
  . "$SNAP/lib/daemon-config"
}

teardown() {
  _teardown_snap_tree
}

# Runs the merge the way the hook does and leaves SVC_RESTART for the test to inspect.
_apply() {
  SVC_RESTART=false
  apply_user_daemon_config
}

@test "rejects a daemon option outside the allowlist and lists the sorted allowlist" {
  local sorted
  sorted="$(printf '%s\n' "${USER_DAEMON_KEYS[@]}" | LC_ALL=C sort | tr '\n' ' ')"
  [ "${USER_DAEMON_KEYS[*]} " = "$sorted" ]
  _snap_config '{"hosts":["tcp://0.0.0.0:2375"]}'
  run reject_unsupported_daemon_config
  [ "$status" -eq 1 ]
  grep -qF "not configurable via snap: hosts" <<<"$output"
  grep -qF "allowed daemon options: ${USER_DAEMON_KEYS[*]}" <<<"$output"
}

@test "rejects a daemon subtree that is not an object, false included" {
  local bad
  for bad in '"foo"' '[1,2]' 'false'; do
    printf '{"daemon":%s}\n' "$bad" > "$SNAPCTL_CONFIG"
    run reject_unsupported_daemon_config
    [ "$status" -eq 1 ]
    grep -qF "daemon options must be set as daemon.<key>=<value>" <<<"$output"
  done
}

@test "accepts allowlisted options and a null (unset) subtree" {
  _snap_config '{"mtu":1400,"dns":["1.1.1.1"]}'
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
  # an absent key reaches the lib as {"daemon":null}
  printf '{}\n' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
}

@test "applies a snap-set option, records its key and keeps the file world-readable" {
  _snap_config '{"mtu":1400}'
  _apply
  [ "$SVC_RESTART" = true ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
  [ "$(find "$SNAP_DATA/config/daemon.json" -perm 644)" = "$SNAP_DATA/config/daemon.json" ]
}

@test "a merge keeps the mode of the file it replaces" {
  # daemon.json can hold credentials (proxies), so a hardened mode has to survive
  chmod 600 "$SNAP_DATA/config/daemon.json"
  _snap_config '{"mtu":1400}'
  _apply
  [ "$(find "$SNAP_DATA/config/daemon.json" -perm 600)" = "$SNAP_DATA/config/daemon.json" ]
}

@test "apply drops snap keys outside the allowlist" {
  # the hook rejects these first; the merge must not rely on that
  _snap_config '{"hosts":["tcp://0.0.0.0:2375"],"mtu":1400}'
  _apply
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
}

@test "a run that changes nothing leaves the file bytes alone" {
  printf '{\n    "log-level":   "error"\n}\n' > "$SNAP_DATA/config/daemon.json"
  _apply
  [ "$SVC_RESTART" = false ]
  grep -qF '"log-level":   "error"' "$SNAP_DATA/config/daemon.json"
  [ "$(_keys)" = '[]' ]
}

@test "unset restores the shipped default, not an earlier hand-set value" {
  _hand '. + {"log-level":"debug"}'
  _snap_config '{"log-level":"info"}'
  _apply
  [ "$(_file)" = '{"log-level":"info"}' ]
  _snap_config '{}'
  _apply
  [ "$(_file)" = '{"log-level":"error"}' ]
}

@test "set/unset round-trips a bool, array, object and null value" {
  _snap_config '{"ipv6":true,"dns":["1.1.1.1","8.8.8.8"],"default-ulimits":{"nofile":{"Name":"nofile","Hard":64000,"Soft":64000}},"bip6":null}'
  _apply
  [ "$SVC_RESTART" = true ]
  [ "$(_file)" = '{"bip6":null,"default-ulimits":{"nofile":{"Hard":64000,"Name":"nofile","Soft":64000}},"dns":["1.1.1.1","8.8.8.8"],"ipv6":true,"log-level":"error"}' ]
  # unsetting the whole subtree arrives as {"daemon":null}; none of these ships a default
  printf '{}\n' > "$SNAPCTL_CONFIG"
  _apply
  [ "$SVC_RESTART" = true ]
  [ "$(_file)" = '{"log-level":"error"}' ]
}

@test "hand edits survive an unrelated snap set, but not one on the same key" {
  _hand '. + {"dns-search":["snap.test"],"log-level":"debug"}'
  _snap_config '{"mtu":1400}'
  _apply
  [ "$(_file)" = '{"dns-search":["snap.test"],"log-level":"debug","mtu":1400}' ]
  _hand '. + {"mtu":9000}'
  _apply
  [ "$SVC_RESTART" = true ]
  [ "$(_file)" = '{"dns-search":["snap.test"],"log-level":"debug","mtu":1400}' ]
}

@test "a hand-deleted shipped key stays deleted until snap config takes it over" {
  _hand 'del(."log-level")'
  _snap_config '{"mtu":1300}'
  _apply
  [ "$(_file)" = '{"mtu":1300}' ]
  _snap_config '{"mtu":1300,"log-level":"info"}'
  _apply
  [ "$(_file)" = '{"log-level":"info","mtu":1300}' ]
  _snap_config '{}'
  _apply
  [ "$(_file)" = '{"log-level":"error"}' ]
}

@test "a dotted sub-key overlay replaces the whole nested tree, not just the leaf" {
  _hand '. + {"default-ulimits":{"nproc":{"hard":99}}}'
  _snap_config '{"default-ulimits":{"nofile":{"hard":64000}}}'
  _apply
  [ "$(_file)" = '{"default-ulimits":{"nofile":{"hard":64000}},"log-level":"error"}' ]
}

@test "keys outside the allowlist pass through untouched" {
  _hand '. + {"max-concurrent-downloads":7,"shutdown-timeout":10000000000000001,"a.b":1,"has space":2,"":3,"h\u00e9llo":4,"nested":[{"x":[1,2,{"y":3}]}]}'
  _snap_config '{"mtu":1400}'
  _apply
  grep -qF '10000000000000001' "$SNAP_DATA/config/daemon.json"
  [ "$(jq -c '[."max-concurrent-downloads", ."a.b", ."has space", .[""], ."h\u00e9llo", .nested]' "$SNAP_DATA/config/daemon.json")" = '[7,1,2,3,4,[{"x":[1,2,{"y":3}]}]]' ]
}

@test "a corrupt key list is discarded rather than partially trusted" {
  # trusting the string entries alone would drop the hand-set dns-search
  _hand '. + {"dns-search":["snap.test"]}'
  printf '["dns-search",1]\n' > "$SNAP_DATA/daemon-config-keys"
  _snap_config '{}'
  _apply
  [ "$(_file)" = '{"dns-search":["snap.test"],"log-level":"error"}' ]
  [ "$(_keys)" = '[]' ]
  _snap_config '{"mtu":1400}'
  _apply
  printf 'not json\n' > "$SNAP_DATA/daemon-config-keys"
  _hand '. + {"max-concurrent-downloads":7}'
  _snap_config '{"mtu":1450}'
  _apply
  [ "$(_file)" = '{"dns-search":["snap.test"],"log-level":"error","max-concurrent-downloads":7,"mtu":1450}' ]
  [ "$(_keys)" = '["mtu"]' ]
  # a file holding two documents is corrupt too: discard it rather than fail the merge
  printf '["mtu"]\n["dns"]\n' > "$SNAP_DATA/daemon-config-keys"
  _hand '. + {"dns":["1.1.1.1"]}'
  _snap_config '{"mtu":1500}'
  _apply
  [ "$(_file)" = '{"dns":["1.1.1.1"],"dns-search":["snap.test"],"log-level":"error","max-concurrent-downloads":7,"mtu":1500}' ]
  [ "$(_keys)" = '["mtu"]' ]
}

@test "a key list naming a non-allowlisted key cannot drop it from the file" {
  _hand '. + {"max-concurrent-downloads":7}'
  printf '["max-concurrent-downloads"]\n' > "$SNAP_DATA/daemon-config-keys"
  _snap_config '{"mtu":1400}'
  _apply
  [ "$(_file)" = '{"log-level":"error","max-concurrent-downloads":7,"mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
}

@test "refuses a daemon.json that is not an object and leaves the key list alone" {
  _snap_config '{"mtu":1400}'
  _apply
  local before bad
  before="$(_keys)"
  for bad in '[]' '' 'null'; do
    printf '%s' "$bad" > "$SNAP_DATA/config/daemon.json"
    run _apply
    [ "$status" -eq 1 ]
    grep -qF "is invalid" <<<"$output"
    [ "$(cat "$SNAP_DATA/config/daemon.json")" = "$bad" ]
    [ "$(_keys)" = "$before" ]
  done
}

@test "reports a pre-existing invalid file rather than blaming the option" {
  _hand '. + {"bad":1}'
  _snap_config '{"mtu":1400}'
  run _apply
  [ "$status" -eq 1 ]
  grep -qF "existing $SNAP_DATA/config/daemon.json is invalid" <<<"$output"
  [ "$(_file)" = '{"bad":1,"log-level":"error"}' ]
}

@test "rejects a value dockerd will not take and cleans up after itself" {
  _snap_config '{"mtu":13}'
  run _apply
  [ "$status" -eq 1 ]
  grep -qF "invalid daemon option value" <<<"$output"
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ "$(ls "$SNAP_DATA/config")" = "daemon.json" ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
}

@test "garbage or empty output from snapctl leaves daemon.json unchanged" {
  cat > "$T/bin/snapctl" <<'GARBAGE'
#!/usr/bin/env bash
printf 'not valid json {'
GARBAGE
  chmod +x "$T/bin/snapctl"
  run _apply
  [ "$status" -eq 1 ]
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
  # empty output means nothing is set: a silent no-op for both entry points
  printf '#!/usr/bin/env bash\n' > "$T/bin/snapctl"
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
  run _apply
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ "$(_keys)" = '[]' ]
}

@test "a failed snapctl read fails both entry points and touches nothing" {
  _snap_config '{"mtu":1400}'
  _apply
  printf 'not json' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 1 ]
  run _apply
  [ "$status" -eq 1 ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
}

@test "a crash between the file and key-list writes strands no key" {
  _hand '. + {"dns-search":["snap.test"]}'
  _snap_config '{"mtu":1400}'
  _apply
  _snap_config '{"mtu":1400,"dns":["1.1.1.1"]}'
  # die at the first key-list write after daemon.json has landed
  (
    mv() {
      if [ "$2" = "$DAEMON_CONFIG_FILE" ]; then
        landed=1
      elif [ "$2" = "$DAEMON_CONFIG_KEYS" ] && [ -n "${landed:-}" ]; then
        exit 1
      fi
      command mv "$@"
    }
    _apply
  ) || true
  [ "$(jq -c .dns "$SNAP_DATA/config/daemon.json")" = '["1.1.1.1"]' ]
  # the widened list covers what snap config applied, and nothing set by hand
  [ "$(_keys)" = '["dns","mtu"]' ]
  # snapd rolls the failed set back
  _snap_config '{"mtu":1400}'
  _apply
  [ "$(_file)" = '{"dns-search":["snap.test"],"log-level":"error","mtu":1400}' ]
}

@test "snapshot and restore put the file and the key list back" {
  _snap_config '{"mtu":1400}'
  _apply
  # no snapshot yet: status 1 and nothing touched
  run restore_daemon_config
  [ "$status" -eq 1 ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
  snapshot_daemon_config
  _hand '. + {"mtu":9}'
  printf 'x' > "$SNAP_DATA/daemon-config-keys"
  restore_daemon_config
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
  # a copy that fails reports it
  snapshot_daemon_config
  _hand '. + {"mtu":9}'
  run bash -c '. "$SNAP/lib/daemon-config"; cp() { return 1; }; restore_daemon_config'
  [ "$status" -ne 0 ]
  [ "$(_file)" = '{"log-level":"error","mtu":9}' ]
}
