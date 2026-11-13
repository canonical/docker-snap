#!/bin/bash

# Invoked in each system before running any test
# Learn more about preparing and restoring: https://github.com/canonical/spread?tab=readme-ov-file#preparing

# shellcheck source=spread/scripts/common.sh
source "$SCRIPTS_PATH/common.sh"

OS_ID="$(. /etc/os-release && echo "$ID")"

if command -v apt-get >/dev/null; then
    echo "Installing snapd"
    sudo apt-get update && sudo apt-get install snapd -y
elif [ "$OS_ID" = centos ]; then
    # CentOS: snapd comes from EPEL and mounts snaps under /var/lib/snapd/snap.
    echo "Installing snapd from EPEL"
    sudo dnf install -y epel-release
    sudo dnf install -y snapd
    sudo systemctl enable --now snapd.socket
    [ -e /snap ] || sudo ln -s /var/lib/snapd/snap /snap
    sudo snap wait system seed.loaded
else
    # Ubuntu Core: snapd is the OS, nothing to install. The image seeds from an
    # old recovery system, so the first boot wants to auto-refresh the boot
    # snaps (kernel/base/snapd) -- and on Core that reboots the machine, which
    # drops spread's session mid-prepare and aborts every task ("snapd is
    # about to reboot the system"). Settle the seed and hold refreshes for the
    # lifetime of this ephemeral guest.
    echo "Ubuntu Core detected; holding snap refreshes"
    sudo snap wait system seed.loaded
    sudo snap refresh --hold || true
    # The hold can land after snapd has started the auto-refresh. Abort only
    # requests the undo, so wait for it, or the next change trips over its
    # tasks ("kernel command line already being updated").
    sudo snap abort --last=auto-refresh 2>/dev/null || true
    # An aborted change ends Undone, which watch reports as an error.
    sudo snap watch '--last=auto-refresh?' 2>/dev/null || true
    # Unwinding a boot snap refresh can leave snapd wanting a reboot, which
    # snap only reports as a warning.
    if sudo snap changes 2>&1 >/dev/null | grep -q "about to reboot"; then
        if [ "$SPREAD_REBOOT" -ge 2 ]; then
            ERROR "snapd still wants a reboot after $SPREAD_REBOOT reboots"
        fi
        REBOOT
    fi
    # The seeded snapd predates fchmodat2 in its seccomp template, which
    # breaks `docker cp`. A named refresh goes through the hold, and snapd
    # alone does not reboot the machine.
    sudo snap refresh snapd
fi

if [ "$OS_ID" = centos ]; then
    # CentOS: sudo's secure_path has no /snap/bin, and every task runs
    # `sudo docker`.
    echo 'Defaults secure_path = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin' \
        | sudo tee /etc/sudoers.d/90-snap-bin >/dev/null
    sudo chmod 0440 /etc/sudoers.d/90-snap-bin
fi

echo "Removing docker (if already installed)"
sudo snap remove docker --purge || true

if [ -n "$SNAP_CHANNEL" ] ; then
    # If $SNAP_CHANNEL was provided, install docker from the store
    echo "Installing docker from channel: $SNAP_CHANNEL"
    sudo snap install docker --channel="$SNAP_CHANNEL"
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

if [ "$OS_ID" = centos ] && ! modinfo nft_compat >/dev/null 2>&1; then
    # CentOS 10: nft_compat and the xt_* matches dockerd's iptables rules
    # need ship only in kernel-modules-extra, which the cloud image omits.
    # Applied after the install, the order a user meets it in.
    echo "nft_compat missing; installing kernel-modules-extra for $(uname -r)"
    sudo dnf install -y "kernel-modules-extra-$(uname -r)"
    restart_docker # from common.sh
fi

# Wait for docker to become online, with a 1 minute timeout
wait_for_docker # from common.sh

echo "Preparation completed"
