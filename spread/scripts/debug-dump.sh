#!/bin/bash
# DEBUG ONLY -- diagnostics for the prepare failures on ppc64el and core.
# Never fails: every probe is best-effort.

section() { printf '\n===== DEBUG: %s =====\n' "$*"; }

debug_snapd_state() {
    section "snapd state ($*)"
    uname -a || true
    snap version || true
    snap list --all || true
    snap changes || true
    local id
    for id in $(snap changes 2>/dev/null | awk 'NR > 1 && $2 != "Done" && $2 != "Error" && $2 != "Undone" && $2 != "Hold" {print $1}'); do
        section "tasks of in-flight change $id"
        snap tasks "$id" || true
    done
}

debug_snapctl_builds() {
    section "snapctl / snapd binaries"
    local f
    for f in /usr/bin/snapctl /usr/lib/snapd/snapd /snap/snapd/current/usr/bin/snapctl /snap/snapd/current/usr/lib/snapd/snapd; do
        [ -e "$f" ] || continue
        printf '%s: %s\n' "$f" "$(grep -a -m1 -o -E 'go1\.[0-9]+(\.[0-9]+)?' "$f" || echo '?')"
    done
}

debug_install_failure() {
    debug_snapd_state "after failed install"
    section "last install change"
    snap tasks --last=install || true
    section "configure hook logs left on disk"
    ls -laR /var/snap/docker/common/hooks 2>/dev/null || echo "none"
    cat /var/snap/docker/common/hooks/*/configure.log 2>/dev/null || true
    section "snapd journal (tail)"
    journalctl -u snapd --no-pager -n 300 || true
    section "kernel log (tail)"
    dmesg | tail -n 50 || true
    debug_snapctl_builds
    section "cpu"
    head -n 20 /proc/cpuinfo || true
}

# Exercise snapctl from inside a snap app, independent of the docker snap.
debug_snapctl_stress() {
    section "snapctl stress via hello-world"
    snap install hello-world >/dev/null 2>&1 || { echo "cannot install hello-world"; return 0; }
    # shellcheck disable=SC2016 # expands inside the snap shell
    snap run --shell hello-world -c '
        crashes=0
        for i in $(seq 50); do
            out="$(snapctl get -d foo 2>&1)" || true
            if grep -q -E "SIG[A-Z]+|goroutine|fatal error" <<<"$out"; then
                crashes=$((crashes + 1))
                [ "$crashes" -gt 1 ] || { echo "attempt $i crashed:"; head -n 60 <<<"$out"; }
            fi
        done
        echo "snapctl get -d: $crashes/50 crashed (last output: $(tail -n 1 <<<"$out"))"
    ' || true
}
