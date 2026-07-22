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
  [ "$status" -ne 0 ]
  [ $((SECONDS - start)) -lt 10 ]
}

@test "returns promptly, not when the killer's sleep expires" {
  local start=$SECONDS out
  out=$(watchdog_run 60 echo prompt-return)
  [ "$out" = prompt-return ]
  [ $((SECONDS - start)) -lt 10 ]
}
