#!/bin/bash -e

# should be sourced from snapcraft.yaml while building Docker
# the necessary patches should be staged into $SNAPCRAFT_STAGE/patches
# current working directory should be the Docker source directory

for patch in "$SNAPCRAFT_STAGE"/patches/*.patch; do
	echo "Applying $(basename "$patch") ..."
	git apply --ignore-space-change --ignore-whitespace "$patch"
	echo
done

export BUILDTIME="$(
	date --rfc-3339 ns 2>/dev/null | sed -e 's/ /T/' \
		|| date -u
)"

export DOCKER_BUILDTAGS='
	apparmor
	seccomp
	selinux
'
#	pkcs11

export AUTO_GOPATH=1
