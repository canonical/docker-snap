#!/bin/bash

# Invoked in each system before running any test
# Learn more about preparing and restoring: https://github.com/canonical/spread?tab=readme-ov-file#preparing

# shellcheck source=spread/scripts/common.sh
source "$SCRIPTS_PATH/common.sh"
# shellcheck source=spread/scripts/debug-dump.sh
source "$SCRIPTS_PATH/debug-dump.sh"

if command -v apt-get >/dev/null; then
    echo "Installing snapd"
    sudo apt-get update && sudo apt-get install snapd -y
else
    # Ubuntu Core: snapd is the OS, nothing to install. The image seeds from an
    # old recovery system, so the first boot wants to auto-refresh the boot
    # snaps (kernel/base/snapd) -- and on Core that reboots the machine, which
    # drops spread's session mid-prepare and aborts every task ("snapd is
    # about to reboot the system"). Settle the seed and hold refreshes for the
    # lifetime of this ephemeral guest.
    echo "Ubuntu Core detected; holding snap refreshes"
    sudo snap wait system seed.loaded
    [ "$SPREAD_REBOOT" != 0 ] || debug_force_race
    sudo snap refresh --hold || true
    # The hold can land after snapd has started the auto-refresh. Abort only
    # requests the undo, so wait for it, or the next change trips over its
    # tasks ("kernel command line already being updated").
    sudo snap abort --last=auto-refresh 2>/dev/null || true
    section "RACE: fix, watching the aborted auto-refresh (reboot $SPREAD_REBOOT)"
    sudo snap watch '--last=auto-refresh?' || true
    debug_snapd_state "core, after watch"
    # Unwinding a boot snap refresh can leave snapd wanting a reboot, which
    # snap only reports as a warning.
    if sudo snap changes 2>&1 >/dev/null | grep -q "about to reboot"; then
        if [ "$SPREAD_REBOOT" -ge 2 ]; then
            ERROR "snapd still wants a reboot after $SPREAD_REBOOT reboots"
        fi
        section "RACE: fix, snapd wants a reboot, REBOOT"
        REBOOT
    fi
    # The seeded snapd predates fchmodat2 in its seccomp template, which
    # breaks `docker cp`. A named refresh goes through the hold, and snapd
    # alone does not reboot the machine.
    debug_snapd_state "core, before snapd refresh"
    if ! sudo snap refresh snapd; then
        debug_snapd_state "core, snapd refresh failed"
        exit 1
    fi
    debug_snapd_state "core, after snapd refresh"
fi

debug_snapctl_builds
debug_snapctl_stress

echo "Removing docker (if already installed)"
sudo snap remove docker --purge || true

if [ -n "$SNAP_CHANNEL" ] ; then
    # If $SNAP_CHANNEL was provided, install docker from the store
    echo "Installing docker from channel: $SNAP_CHANNEL"
    if ! sudo snap install docker --channel="$SNAP_CHANNEL"; then
        debug_install_failure
        debug_snapctl_stress
        # A failed refresh keeps $SNAP_COMMON, so the full hook log survives.
        section "retry: stable first, then refresh to $SNAP_CHANNEL"
        if sudo snap install docker --channel=latest/stable; then
            echo "latest/stable installed fine: $(snap list docker | tail -n 1)"
            sudo snap refresh docker --channel="$SNAP_CHANNEL" || true
            debug_install_failure
        else
            echo "latest/stable failed too"
            debug_install_failure
        fi
        exit 1
    fi
elif [ -n "$SNAP_FILE" ] ; then
    echo "Installing local snap: $SNAP_FILE"
    sudo snap install "$SNAP_FILE" --dangerous

    echo "Connecting interfaces"

    # sudo snap connect docker:gpu-2404 mesa-2404:gpu-2404 || true # not connected because we don't do any graphics tests
    sudo snap connect docker:docker-cli        docker:docker-daemon
    sudo snap connect docker:privileged
    sudo snap connect docker:support
    sudo snap connect docker:firewall-control
    sudo snap connect docker:home
    sudo snap connect docker:network
    sudo snap connect docker:network-bind
    sudo snap connect docker:network-control
    sudo snap connect docker:opengl

    # Restart docker and keep on retrying on failure
    echo "Restarting docker"
    restart_docker # from common.sh
else
    ERROR "No SNAP_CHANNEL nor SNAP_FILE provided"
fi

# Wait for docker to become online, with a 1 minute timeout
wait_for_docker # from common.sh

echo "Preparation completed"

# DEBUG ONLY: spread prints script output only on failure, so fail on purpose.
section "prepare reached the end, failing on purpose to surface the output"
exit 1
