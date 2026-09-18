#!/bin/bash
# Sourced library: watchdog_run <timeout> <command>...
#
# Run a command under a wall-clock bound: kill it once the timeout expires,
# otherwise pass its status and output through. timeout(1) is not shipped
# in the image-garden snap and the host binary is blocked by confinement,
# hence hand-rolled.
#
# NOTE: the killer's stdout/stderr are redirected to /dev/null. Otherwise
#       its orphaned sleep would inherit and hold the caller's output pipe
#       open, and a command substitution around watchdog_run (or spread
#       itself, reading the allocate hook's output) would block until the
#       sleep expired.
watchdog_run() {
  local timeout="$1"
  shift
  local pid killer status=0
  "$@" &
  pid=$!
  # The killer gets no inherited fds (stdin/stdout/stderr to /dev/null,
  # bats' fd 3 closed): anything its sleep keeps open, the caller may sit
  # waiting on (spread reads our stdout; a terminal or bats waits on the
  # tty / fd 3).
  ( sleep "$timeout"; kill "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 3>&- &
  killer=$!
  wait "$pid" || status=$?
  # Reap the killer's sleep before the killer itself: killing only the
  # subshell would orphan the sleep, which then lingers for the full
  # timeout (holding whatever fds slipped through above).
  pkill -P "$killer" 2>/dev/null || true
  kill "$killer" 2>/dev/null || true
  return "$status"
}
