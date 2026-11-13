#!/bin/bash
# State dump for spread's debug hooks: after a failed project prepare or
# restore, and after every failed task. The system may be half set up, so
# every probe may fail without stopping the rest.

section() {
  printf '\n=== %s\n' "$*"
}

section "system"
uname -a
uptime
free -m
df -h / /var/snap 2>/dev/null

section "snaps"
snap version
snap list
snap changes | tail -n 5
snap connections docker

section "dockerd"
systemctl status --no-pager --lines=0 'snap.docker.*'
journalctl -u snap.docker.dockerd --no-pager -n 100
docker ps -a

# The snap's iptables wrapper picks nft or legacy per call, so dump both.
section "firewall as the snap sees it"
# shellcheck disable=SC2016 # expands inside the snap's shell, not here
snap run --shell docker.dockerd -c '
  nft list ruleset >/dev/null 2>&1; echo "nft list ruleset exit: $?"
  echo "--- nft backend"; xtables-nft-multi iptables-save 2>&1
  echo "--- legacy backend"; xtables-legacy-multi iptables-save 2>&1
'
lsmod | grep -E '^(nf_tables|nft_compat|ip_tables|x_tables|xt_|br_netfilter|overlay) '

section "kernel and LSM denials"
journalctl -k --no-pager -n 300 | grep -E 'apparmor="DENIED"|avc: +denied|Out of memory|segfault' | tail -n 30
command -v ausearch >/dev/null && ausearch -m avc -ts recent 2>/dev/null | grep -E '^type=AVC' | tail -n 30

exit 0
