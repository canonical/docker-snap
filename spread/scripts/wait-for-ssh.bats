#!/usr/bin/env bats
# Tests for wait_for_ssh. Run with: bats spread/scripts/
#
# A small python listener stands in for sshd; python3 is available both on
# the CI runners and on developer machines, unlike any one flavour of nc.

setup() {
  source "$BATS_TEST_DIRNAME/wait-for-ssh.sh"
  LISTENER_PID=""
}

teardown() {
  if [ -n "$LISTENER_PID" ]; then
    kill "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
  fi
}

# Serve $1 as the connection banner on an ephemeral port; sets PORT.
start_listener() {
  python3 -c '
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(5)
print(s.getsockname()[1], flush=True)
while True:
    c, _ = s.accept()
    c.sendall(sys.argv[1].encode())
    c.close()
' "$1" > "$BATS_TEST_TMPDIR/port" &
  LISTENER_PID=$!
  local i
  for ((i = 0; i < 50; i++)); do
    [ -s "$BATS_TEST_TMPDIR/port" ] && break
    sleep 0.1
  done
  PORT=$(cat "$BATS_TEST_TMPDIR/port")
  [ -n "$PORT" ]
}

# An ephemeral port with nothing listening on it.
free_port() {
  python3 -c '
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
'
}

@test "ready when the listener talks ssh" {
  start_listener $'SSH-2.0-bats\r\n'
  wait_for_ssh 127.0.0.1 "$PORT" 3 0.1
}

@test "a non-ssh banner is not ready" {
  start_listener $'HTTP/1.0 200 OK\r\n'
  run wait_for_ssh 127.0.0.1 "$PORT" 3 0.1
  [ "$status" -eq 1 ]
}

@test "an unreachable port times out" {
  run wait_for_ssh 127.0.0.1 "$(free_port)" 3 0.1
  [ "$status" -eq 1 ]
}

@test "a ready daemon is picked up without sleeping" {
  start_listener $'SSH-2.0-bats\r\n'
  local start=$SECONDS
  wait_for_ssh 127.0.0.1 "$PORT" 3 60
  [ $((SECONDS - start)) -lt 10 ]
}
