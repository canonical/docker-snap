#!/usr/bin/env bats
# Tests for watchdog_run. Run with: bats spread/scripts/
#
# The elapsed-time assertions are regression tests for the orphaned-sleep
# bug: the killer's sleep used to inherit the caller's output pipe, so a
# command substitution around watchdog_run blocked for the full timeout
# even after the command had finished.

setup() {
  source "$BATS_TEST_DIRNAME/watchdog.sh"
}

@test "passes through output and success" {
  local out
  out=$(watchdog_run 5 echo hello)
  [ "$out" = hello ]
}

@test "propagates the command's failure status" {
  run watchdog_run 5 bash -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "kills a command that outlives the timeout" {
  local start=$SECONDS
  run watchdog_run 1 sleep 60
  [ "$status" -eq 143 ] # 128 + SIGTERM: the caller-visible contract
  [ $((SECONDS - start)) -lt 10 ]
}

@test "escalates to SIGKILL for a TERM-ignoring command" {
  local start=$SECONDS
  WATCHDOG_KILL_GRACE=1 run watchdog_run 1 \
    bash -c 'trap "" TERM; while true; do sleep 0.2; done'
  [ "$status" -eq 137 ] # 128 + SIGKILL
  [ $((SECONDS - start)) -lt 8 ]
}

@test "preserves command arguments" {
  local out
  out=$(watchdog_run 5 bash -c 'printf "%s|" "$@"' -- "a b" "c")
  [ "$out" = "a b|c|" ]
}

@test "passes the command's stderr through" {
  run watchdog_run 5 bash -c 'echo oops >&2'
  [ "$status" -eq 0 ]
  [[ "$output" == *oops* ]]
}

@test "leaves no processes behind" {
  watchdog_run 5432 true
  local i
  for ((i = 0; i < 10; i++)); do
    pgrep -f 'sleep 5432' >/dev/null || break
    sleep 0.1
  done
  ! pgrep -f 'sleep 5432'
}

@test "returns promptly, not when the killer's sleep expires" {
  local start=$SECONDS out
  out=$(watchdog_run 5 echo prompt-return)
  [ "$out" = prompt-return ]
  [ $((SECONDS - start)) -lt 4 ]
}
