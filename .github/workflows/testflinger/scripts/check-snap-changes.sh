#!/usr/bin/env bash

# This script is adapted from
# https://github.com/canonical/hwcert-jenkins-tools/blob/c5cf512d968100db90998abe61c474de0be681ca/scriptlets/check_for_snap_changes

echo "Get snap changes"

# list the snap changes on the device and store the output in a temp file;
# clean it up on every exit path, this script runs in ssh polling loops
OUTPUT=$(mktemp)
trap 'rm -f "$OUTPUT"' EXIT
snap changes > "$OUTPUT"

RESULT=$?
if [ ! "$RESULT" -eq 0 ]; then exit $RESULT; fi

# tail -n +2: remove the header
# awk 'NF {print $2}': print the second column on non-empty lines (i.e. the status)
# grep -qxE "...": succeed when a status token says changes are ongoing or pending
tail -n +2 "$OUTPUT" | \
awk 'NF {print $2}' | \
grep -qxE "(Doing|Undoing|Wait|Do|Undo)"

# shellcheck disable=SC2181  # $? checks the multi-stage pipeline above; folding it into the if would hurt readability
if [ "$?" -eq 0 ]; then
    # changes are still ongoing or pending: display output as a diagnostic
    grep -wE "(Doing|Undoing|Wait|Do|Undo)" "$OUTPUT"

    exit 1
fi

echo "No ongoing or pending snap changes"
