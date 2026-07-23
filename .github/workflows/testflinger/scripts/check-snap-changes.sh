#!/usr/bin/env bash

# This script is adapted from
# https://github.com/canonical/hwcert-jenkins-tools/blob/c5cf512d968100db90998abe61c474de0be681ca/scriptlets/check_for_snap_changes

echo "Get snap changes"

# list the snap changes on the device and store the output in a temp file
OUTPUT=$(mktemp)
snap changes > "$OUTPUT"

RESULT=$?
if [ ! "$RESULT" -eq 0 ]; then exit $RESULT; fi

# tail -n +2: remove the header
# awk 'NF {print $2}': print the second column on non-empty lines (i.e. the status)
# grep -q -E "...": succeed when changes are still ongoing or pending
tail -n +2 "$OUTPUT" | \
awk 'NF {print $2}' | \
grep -q -E "\b(Doing|Undoing|Wait|Do|Undo)\b"

# shellcheck disable=SC2181  # $? checks the multi-stage pipeline above; folding it into the if would hurt readability
if [ "$?" -eq 0 ]; then
    # changes are still ongoing or pending: display output as a diagnostic
    grep -E "\b(Doing|Undoing|Wait|Do|Undo)\b" "$OUTPUT"
    rm "$OUTPUT"

    exit 1
fi

echo "No ongoing or pending snap changes"
rm "$OUTPUT"
