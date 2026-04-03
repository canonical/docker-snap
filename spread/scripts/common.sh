#!/bin/bash

wait_for_docker() {
    num_tries=0
	MAX_DOCKER_TRIES=60
    until docker info; do
        sleep 1
        num_tries=$((num_tries+1))
        if (( num_tries > MAX_DOCKER_TRIES )); then
            ERROR "max tries waiting for docker daemon to come online"
        fi
    done 
}
