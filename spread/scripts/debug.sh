#!/bin/bash
# Run by the project and task debug hooks in spread.yaml once something failed.
# The system may be half set up, so every probe is allowed to fail.

section() {
  printf '\n=== %s\n' "$*"
}

section "snapd and snaps"
snap version
snap list
snap connections docker

section "dockerd"
systemctl status --no-pager snap.docker.dockerd
journalctl -u snap.docker.dockerd --no-pager -n 300

# The snap's iptables wrapper picks nft or legacy on every call, from these.
section "iptables as the snap sees it"
# shellcheck disable=SC2016 # expands inside the snap's shell, not here
snap run --shell docker.dockerd -c '
  nft list ruleset >/dev/null 2>&1; echo "nft list ruleset exit: $?"
  echo "host iptables resolves to: $(readlink -f /var/lib/snapd/hostfs/sbin/iptables)"
  echo "--- nft backend"; xtables-nft-multi iptables-save 2>&1
  echo "--- legacy backend"; xtables-legacy-multi iptables-save 2>&1
'

section "host nft ruleset"
nft list ruleset

section "netfilter modules"
lsmod | grep -E '^(xt_|nft_compat|ip_tables|iptable_|nf_tables|br_netfilter|bridge)'

section "SELinux"
command -v getenforce >/dev/null && getenforce
ausearch -m avc -ts recent 2>/dev/null | tail -n 50

exit 0
