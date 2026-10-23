#!/usr/bin/env bats
# Tests for the driver root detection in nvidia/lib, with the host filesystem, snapctl
# and nvidia-ctk faked. The fake nvidia-ctk records its arguments one per line.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  export SNAP="$TMP/snap" SNAP_DATA="$TMP/data"
  mkdir -p "$SNAP/usr/bin" "$SNAP_DATA"
  cat > "$SNAP/usr/bin/nvidia-ctk" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$SNAP_DATA/nvidia-ctk.args"
echo "$XDG_DATA_DIRS" > "$SNAP_DATA/nvidia-ctk.xdg"
EOF
  chmod +x "$SNAP/usr/bin/nvidia-ctk"
  snapctl() { :; }
  unset NVIDIA_DRIVER_ROOT
  # shellcheck source=../nvidia/lib
  . "$REPO/nvidia/lib"
  HOSTFS="$TMP/hostfs"
}

teardown() {
  rm -rf "$TMP"
}

_libcuda() {
  mkdir -p "$HOSTFS/$1"
  touch "$HOSTFS/$1/libcuda.so.580.0"
  ln -s libcuda.so.580.0 "$HOSTFS/$1/libcuda.so.1"
}

_driver_root() {
  grep -A1 -x -- --driver-root "$SNAP_DATA/nvidia-ctk.args" | tail -1
}

@test "detects classic with a Debian multiarch layout" {
  _libcuda "usr/lib/$ARCH_TRIPLET"
  nvidia_support_classic
}

@test "detects classic with a Fedora lib64 layout" {
  _libcuda usr/lib64
  nvidia_support_classic
}

@test "detects classic with an Arch flat lib layout" {
  _libcuda usr/lib
  nvidia_support_classic
}

@test "no classic support without libcuda.so.1 on the host" {
  mkdir -p "$HOSTFS/usr/lib"
  ! nvidia_support_classic
}

@test "classic generates against the host fs as driver root" {
  _libcuda usr/lib
  cdi_generate
  [ "$(_driver_root)" = "$HOSTFS" ]
  grep -qx -- --dev-root "$SNAP_DATA/nvidia-ctk.args"
  ! grep -qx -- --library-search-path "$SNAP_DATA/nvidia-ctk.args"
}

@test "classic wins over a connected core content provider" {
  _libcuda usr/lib
  NVIDIA_DRIVER_ROOT=/somewhere cdi_generate
  [ "$(_driver_root)" = "$HOSTFS" ]
}

@test "UC24 generates against NVIDIA_DRIVER_ROOT" {
  NVIDIA_DRIVER_ROOT=/kernel-gpu cdi_generate
  [ "$(_driver_root)" = /kernel-gpu ]
}

@test "UC22 generates against the graphics content dir" {
  mkdir -p "$SNAP/graphics/lib/$ARCH_TRIPLET"
  cdi_generate
  [ "$(_driver_root)" = "$SNAP/graphics" ]
  [ "$(cat "$SNAP_DATA/nvidia-ctk.xdg")" = /usr/local/share:/usr/share:/share ]
}

@test "falls back to the snap base as driver root" {
  cdi_generate
  [ "$(_driver_root)" = / ]
}
