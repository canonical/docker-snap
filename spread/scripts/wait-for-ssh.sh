#!/bin/bash
# Sourced library: wait_for_ssh <host> <port> [attempts] [interval]
#
# Poll until an ssh daemon answers on host:port, by connecting and reading
# the first four bytes of its banner ("SSH-"). A bare tcp connect is not
# proof of anything: qemu's slirp port-forward accepts connections as soon
# as it exists, well before the guest's sshd is up. Returns 0 once the
# banner is seen, 1 when the attempts run out. Checks first, sleeps after
# a failed check only, so a ready daemon is picked up immediately.

_ssh_banner_ready() {
  (
    exec 3<>"/dev/tcp/$1/$2" || exit 1
    banner=""
    IFS= read -r -t 10 -n 4 banner <&3 || true
    [ "$banner" = "SSH-" ]
  ) 2>/dev/null
}

wait_for_ssh() {
  local host="$1"
  local port="$2"
  local attempts="${3:-120}"
  local interval="${4:-5}"
  local i
  for ((i = 0; i < attempts; i++)); do
    if _ssh_banner_ready "$host" "$port"; then
      return 0
    fi
    sleep "$interval"
  done
  return 1
}
