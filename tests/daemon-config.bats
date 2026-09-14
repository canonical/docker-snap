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

@test "rejects a daemon option outside the allowlist" {
  _snap_config '{"hosts":["tcp://0.0.0.0:2375"]}'
  run reject_unsupported_daemon_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"not configurable via snap: hosts"* ]]
  [[ "$output" == *"allowed daemon options:"* ]]
}

@test "rejects a scalar daemon subtree with a message" {
  printf '{"daemon":"foo"}\n' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"daemon options must be set as daemon.<key>=<value>"* ]]
}

@test "accepts allowlisted options and an unset subtree" {
  _snap_config '{"mtu":1400,"dns":["1.1.1.1"]}'
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
  printf '{}\n' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
}

@test "applies a snap-set option and records its key" {
  _snap_config '{"mtu":1400}'
  _apply
  [ "$SVC_RESTART" = true ]
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

@test "unset restores the shipped default" {
  _snap_config '{"log-level":"debug"}'
  _apply
  [ "$(_file)" = '{"log-level":"debug"}' ]
  _snap_config '{}'
  _apply
  [ "$(_file)" = '{"log-level":"error"}' ]
}

@test "unset removes an option the snap ships no default for" {
  _snap_config '{"mtu":1400}'
  _apply
  _snap_config '{}'
  _apply
  [ "$SVC_RESTART" = true ]
  [ "$(_file)" = '{"log-level":"error"}' ]
}

@test "hand edits survive an unrelated snap set" {
  _hand '. + {"dns-search":["snap.test"],"log-level":"debug"}'
  _snap_config '{"mtu":1400}'
  _apply
  [ "$(_file)" = '{"dns-search":["snap.test"],"log-level":"debug","mtu":1400}' ]
}

@test "a snap-set key overwrites a hand edit to it on the next run" {
  _snap_config '{"mtu":1400}'
  _apply
  _hand '. + {"mtu":9000}'
  _apply
  [ "$SVC_RESTART" = true ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
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

@test "a new shipped default leaves a key that was never snap-set alone" {
  _apply
  printf '{"log-level":"warn"}\n' > "$SNAP/config/daemon.json"
  _apply
  [ "$SVC_RESTART" = false ]
  [ "$(_file)" = '{"log-level":"error"}' ]
}

@test "keys outside the allowlist pass through untouched" {
  _hand '. + {"max-concurrent-downloads":7,"shutdown-timeout":10000000000000001}'
  _snap_config '{"mtu":1400}'
  _apply
  grep -qF '10000000000000001' "$SNAP_DATA/config/daemon.json"
  [ "$(jq -c '."max-concurrent-downloads"' "$SNAP_DATA/config/daemon.json")" = 7 ]
}

@test "an unreadable key list is discarded" {
  _snap_config '{"mtu":1400}'
  _apply
  printf 'not json\n' > "$SNAP_DATA/daemon-config-keys"
  _hand '. + {"max-concurrent-downloads":7}'
  _snap_config '{"mtu":1450}'
  _apply
  [ "$(_file)" = '{"log-level":"error","max-concurrent-downloads":7,"mtu":1450}' ]
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

@test "a key list with a non-string entry is discarded rather than partially trusted" {
  _hand '. + {"dns-search":["snap.test"]}'
  printf '["dns-search",1]\n' > "$SNAP_DATA/daemon-config-keys"
  _snap_config '{}'
  _apply
  # trusting the string entries alone would drop the hand-set dns-search
  [ "$(_file)" = '{"dns-search":["snap.test"],"log-level":"error"}' ]
  [ "$(_keys)" = '[]' ]
}

@test "refuses a daemon.json that is not an object" {
  printf '[]\n' > "$SNAP_DATA/config/daemon.json"
  _snap_config '{"mtu":1400}'
  run _apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"is invalid"* ]]
  [ "$(cat "$SNAP_DATA/config/daemon.json")" = '[]' ]
}

@test "reports a pre-existing invalid file rather than blaming the option" {
  _hand '. + {"bad":1}'
  _snap_config '{"mtu":1400}'
  run _apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"existing $SNAP_DATA/config/daemon.json is invalid"* ]]
  [ "$(_file)" = '{"bad":1,"log-level":"error"}' ]
}

@test "rejects a value dockerd will not take and cleans up after itself" {
  _snap_config '{"mtu":13}'
  run _apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid daemon option value"* ]]
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ "$(ls "$SNAP_DATA/config")" = "daemon.json" ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
}

@test "snapshot and restore put the file and the key list back" {
  _snap_config '{"mtu":1400}'
  _apply
  snapshot_daemon_config
  _hand '. + {"mtu":9}'
  printf 'x' > "$SNAP_DATA/daemon-config-keys"
  restore_daemon_config
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '["mtu"]' ]
  # nothing to put back this time: status 1 tells the hook no restart is needed
  run restore_daemon_config
  [ "$status" -eq 1 ]
}

@test "accepts bip6 and ipv6 as allowlisted options" {
  _snap_config '{"bip6":"2001:db8:1::/64","ipv6":true}'
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
}

@test "merges a nested-object option like default-ulimits verbatim" {
  _snap_config '{"default-ulimits":{"nofile":{"Name":"nofile","Hard":64000,"Soft":64000}}}'
  _apply
  [ "$SVC_RESTART" = true ]
  [ "$(_file)" = '{"default-ulimits":{"nofile":{"Hard":64000,"Name":"nofile","Soft":64000}},"log-level":"error"}' ]
}

@test "a second run with unchanged snap config leaves a hand edit alone" {
  _hand '. + {"dns-search":["snap.test"]}'
  _snap_config '{"mtu":1400}'
  _apply
  local before
  before="$(_file)"
  _apply
  # a re-run (on refresh, or for another snap set) must not clobber a hand edit
  [ "$SVC_RESTART" = false ]
  [ "$(_file)" = "$before" ]
  [ "$(_keys)" = '["mtu"]' ]
}

@test "a dotted sub-key overlay replaces the whole nested tree, not just the leaf" {
  _hand '. + {"default-ulimits":{"nproc":{"hard":99}}}'
  _snap_config '{"default-ulimits":{"nofile":{"hard":64000}}}'
  _apply
  [ "$(_file)" = '{"default-ulimits":{"nofile":{"hard":64000}},"log-level":"error"}' ]
}

@test "a lost key list leaves an unset value stuck in the file" {
  _snap_config '{"mtu":1400}'
  _apply
  rm -f "$SNAP_DATA/daemon-config-keys"
  _snap_config '{}'
  _apply
  # limitation: the key list is the only record of what snap config applied
  [ "$SVC_RESTART" = false ]
  [ "$(_file)" = '{"log-level":"error","mtu":1400}' ]
  [ "$(_keys)" = '[]' ]
}

@test "set/unset round-trips a bool, array, object and null value" {
  _snap_config '{"ipv6":true,"dns":["1.1.1.1","8.8.8.8"],"default-ulimits":{"nofile":{"hard":64000,"soft":32000}},"bip6":null}'
  _apply
  [ "$(_file)" = '{"bip6":null,"default-ulimits":{"nofile":{"hard":64000,"soft":32000}},"dns":["1.1.1.1","8.8.8.8"],"ipv6":true,"log-level":"error"}' ]
  _snap_config '{}'
  _apply
  [ "$(_file)" = '{"log-level":"error"}' ]
}

@test "a non-object daemon.json leaves the key list alone" {
  _snap_config '{"mtu":1400}'
  _apply
  local before
  before="$(_keys)"
  printf '[]\n' > "$SNAP_DATA/config/daemon.json"
  run _apply
  [ "$status" -eq 1 ]
  grep -qF "is invalid" <<<"$output"
  [ "$(_keys)" = "$before" ]
}

@test "the allowlist is sorted and the reject message lists it in full" {
  local sorted
  sorted="$(printf '%s\n' "${USER_DAEMON_KEYS[@]}" | LC_ALL=C sort | tr '\n' ' ')"
  [ "${USER_DAEMON_KEYS[*]} " = "$sorted" ]
  _snap_config '{"hosts":["tcp://0.0.0.0:2375"]}'
  run reject_unsupported_daemon_config
  [ "$status" -eq 1 ]
  grep -qF "allowed daemon options: ${USER_DAEMON_KEYS[*]}" <<<"$output"
}

@test "garbage from snapctl leaves daemon.json unchanged and warns" {
  cat > "$T/bin/snapctl" <<'GARBAGE'
#!/usr/bin/env bash
printf 'not valid json {'
GARBAGE
  chmod +x "$T/bin/snapctl"
  run _apply
  [ "$status" -eq 0 ]
  grep -qF "could not read daemon options; leaving daemon.json unchanged" <<<"$output"
  [ "$(_file)" = '{"log-level":"error"}' ]
  [ ! -e "$SNAP_DATA/daemon-config-keys" ]
}

@test "a null daemon subtree is treated as unset" {
  printf '{"daemon":null}\n' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
}

@test "rejects a false daemon subtree instead of reading it as unset" {
  printf '{"daemon":false}\n' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 1 ]
  grep -qF "daemon options must be set as daemon.<key>=<value>" <<<"$output"
}

@test "rejects an array daemon subtree with the same message as a scalar" {
  printf '{"daemon":[1,2]}\n' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 1 ]
  grep -qF "daemon options must be set as daemon.<key>=<value>" <<<"$output"
}

@test "refuses an empty or null daemon.json" {
  : > "$SNAP_DATA/config/daemon.json"
  _snap_config '{"mtu":1400}'
  run _apply
  [ "$status" -eq 1 ]
  grep -qF "is invalid" <<<"$output"
  [ ! -s "$SNAP_DATA/config/daemon.json" ]

  printf 'null\n' > "$SNAP_DATA/config/daemon.json"
  run _apply
  [ "$status" -eq 1 ]
  grep -qF "is invalid" <<<"$output"
  [ "$(cat "$SNAP_DATA/config/daemon.json")" = 'null' ]
}

@test "the merged file is written with mode 644" {
  _snap_config '{"mtu":1400}'
  _apply
  [ "$(find "$SNAP_DATA/config/daemon.json" -perm 644)" = "$SNAP_DATA/config/daemon.json" ]
}

@test "restore without a snapshot returns 1 and touches nothing" {
  _snap_config '{"mtu":1400}'
  _apply
  local before_file before_keys
  before_file="$(cat "$SNAP_DATA/config/daemon.json")"
  before_keys="$(_keys)"
  # pin: no snapshot was ever taken -- distinct from restoring twice in a row
  run restore_daemon_config
  [ "$status" -eq 1 ]
  [ "$(cat "$SNAP_DATA/config/daemon.json")" = "$before_file" ]
  [ "$(_keys)" = "$before_keys" ]
}

@test "reject returns success when snapctl itself prints nothing" {
  printf 'not json' > "$SNAPCTL_CONFIG"
  run reject_unsupported_daemon_config
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an empty allowlist makes apply_user_daemon_config a pure no-op" {
  USER_DAEMON_KEYS=()
  _hand '. + {"max-concurrent-downloads":7}'
  _snap_config '{"mtu":1400,"dns":["1.1.1.1"]}'
  _apply
  [ "$SVC_RESTART" = false ]
  [ "$(_file)" = '{"log-level":"error","max-concurrent-downloads":7}' ]
}

@test "unusual non-allowlisted keys and values pass through untouched" {
  _hand '. + {"a.b":1,"has space":2,"":3,"h\u00e9llo":4,"nested":[{"x":[1,2,{"y":3}]}]}'
  _snap_config '{"mtu":1400}'
  _apply
  [ "$(jq -c '."a.b"' "$SNAP_DATA/config/daemon.json")" = 1 ]
  [ "$(jq -c '."has space"' "$SNAP_DATA/config/daemon.json")" = 2 ]
  [ "$(jq -c '.[""]' "$SNAP_DATA/config/daemon.json")" = 3 ]
  [ "$(jq -c '."h\u00e9llo"' "$SNAP_DATA/config/daemon.json")" = 4 ]
  [ "$(jq -c '.nested' "$SNAP_DATA/config/daemon.json")" = '[{"x":[1,2,{"y":3}]}]' ]
}
