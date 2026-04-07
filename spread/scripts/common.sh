#!/bin/bash

wait_for_docker() {
    num_tries=0
	MAX_TRIES=60

    until docker info; do
        num_tries=$((num_tries+1))
        if (( num_tries > MAX_TRIES )); then
            ERROR "max tries waiting for docker daemon to come online"
        fi
        sleep 1
    done
}

restart_docker() {
    num_tries=0
	MAX_TRIES=5

    until snap restart docker;; do
        num_tries=$((num_tries+1))
        if (( num_tries > MAX_TRIES )); then
            ERROR "docker daemon failed to restart"
        fi
        sleep 5
    done
}
