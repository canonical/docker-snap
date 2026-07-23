#!/usr/bin/env bats
# Tests for check-snap-changes.sh: succeeds (exit 0) when no snap changes are
# ongoing or pending, fails (exit 1) while any are in flight. `snap` is mocked
# on PATH so the parsing logic is exercised without a real snapd.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/check-snap-changes.sh"
  MOCK_DIR="$(mktemp -d)"
  PATH="$MOCK_DIR:$PATH"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# _mock_snap <exit-code> <canned `snap changes` output>
# Installs a fake `snap` that prints the given output for `snap changes` and
# exits with the given code.
_mock_snap() {
  local code="$1"
  printf '%s\n' "$2" > "$MOCK_DIR/snap_changes_output"
  cat > "$MOCK_DIR/snap" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "changes" ]; then
  cat "$MOCK_DIR/snap_changes_output"
fi
exit $code
EOF
  chmod +x "$MOCK_DIR/snap"
}

@test "exits 0 when there are no changes (header only)" {
  _mock_snap 0 "ID   Status  Spawn  Ready  Summary"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No ongoing or pending snap changes"* ]]
}

@test "exits 0 when all changes are Done" {
  _mock_snap 0 "ID   Status  Spawn               Ready               Summary
4    Done    today at 12:05 UTC  today at 12:06 UTC  Auto-refresh snap \"pc-kernel\""
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No ongoing or pending snap changes"* ]]
}

@test "exits 1 when a change is Doing" {
  _mock_snap 0 "ID   Status  Spawn               Ready  Summary
3    Doing   today at 12:05 UTC  -      Auto-refresh snap \"pc-kernel\""
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "exits 1 when a change is pending (Do)" {
  _mock_snap 0 "ID   Status  Spawn               Ready  Summary
5    Do      today at 12:06 UTC  -      Refresh snaps"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# COVER: the "Done" status must not match the \bDo\b pattern; this guards the
# word-boundary in the grep against a false positive on completed changes.
@test "Done is not mistaken for the Do status" {
  _mock_snap 0 "ID   Status  Spawn               Ready               Summary
6    Done    today at 12:05 UTC  today at 12:06 UTC  Refresh snaps"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# COVER: a non-zero `snap changes` exit must propagate, not be read as "clean".
@test "propagates a snap command failure" {
  _mock_snap 7 ""
  run bash "$SCRIPT"
  [ "$status" -eq 7 ]
}
