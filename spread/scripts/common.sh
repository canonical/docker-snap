#!/bin/bash

# Retry a command until it succeeds, for assertions that only converge after
# some time (container state transitions, restart counters, daemon startup).
# Emulated systems can be slow enough that a fixed sleep before a one-shot
# assertion fails even though the system is healthy. Pass a function name if
# the check needs command substitution: arguments are evaluated once at call
# time, so an inline $(...) would retry a frozen value.
run_retry_command() {
    local RETRIES=30
    local DELAY=6
    local n=1
    until "$@"; do
        if (( n >= RETRIES )); then
            ERROR "Command failed after $RETRIES attempts: $*"
        fi
        echo "Command failed (attempt $n/$RETRIES): $*. Retrying in $DELAY seconds..."
        n=$((n+1))
        sleep $DELAY
    done
}

wait_for_docker() {
    echo "Waiting for docker to become available..."
    run_retry_command docker info
}

restart_docker() {
    echo "Restarting docker daemon..."
    run_retry_command sudo snap restart docker
}
