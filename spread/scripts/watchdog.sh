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
  # fd 3 is closed for the same reason stdout/stderr are silenced: the
  # sleep can outlive us as an orphan, and anything it keeps open, the
  # caller may sit waiting on (spread reads our stdout; bats waits on its
  # fd 3).
  ( sleep "$timeout"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 3>&- &
  killer=$!
  wait "$pid" || status=$?
  kill "$killer" 2>/dev/null || true
  return "$status"
}
