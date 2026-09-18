#!/bin/bash
# Sourced library: wait_for_ssh <host> <port> [timeout] [interval] [banner_timeout]
#
# Poll until an ssh daemon answers on host:port, by connecting and reading
# the first four bytes of its banner ("SSH-"). A bare tcp connect is not
# proof of anything: qemu's slirp port-forward accepts connections as soon
# as it exists, well before the guest's sshd is up. Returns 0 once the
# banner is seen, 1 once timeout seconds (default 600) have passed. Checks
# first, sleeps interval seconds (default 5) after a failed check only, so a
# ready daemon is picked up immediately.
#
# A connection that is accepted but stays silent (the slirp case above) holds
# each check for up to banner_timeout seconds (default 10). That wait is
# clamped to what is left of the timeout, so the overall bound is the timeout
# plus at most one interval. The tcp connect itself is not bounded: that holds
# for a local port-forward, which accepts or refuses at once, but not for a
# host that drops packets.

_ssh_banner_ready() {
  (
    exec 3<>"/dev/tcp/$1/$2" || exit 1
    banner=""
    IFS= read -r -t "$3" -n 4 banner <&3 || true
    [ "$banner" = "SSH-" ]
  ) 2>/dev/null
}

wait_for_ssh() {
  local host="$1"
  local port="$2"
  local timeout="${3:-600}"
  local interval="${4:-5}"
  local banner_timeout="${5:-10}"
  local deadline=$((SECONDS + timeout))
  local remaining
  while ((SECONDS < deadline)); do
    remaining=$((deadline - SECONDS))
    if _ssh_banner_ready "$host" "$port" "$((remaining < banner_timeout ? remaining : banner_timeout))"; then
      return 0
    fi
    sleep "$interval"
  done
  return 1
}
