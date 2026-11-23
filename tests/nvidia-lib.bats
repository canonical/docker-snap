#!/usr/bin/env bats
# Tests for the host lib dir detection in nvidia/lib, with the host filesystem, snapctl
# and nvidia-ctk faked. The fake nvidia-ctk records its arguments one per line.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  export SNAP="$TMP/snap" SNAP_DATA="$TMP/data"
  mkdir -p "$SNAP/usr/bin" "$SNAP_DATA"
  cat > "$SNAP/usr/bin/nvidia-ctk" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$SNAP_DATA/nvidia-ctk.args"
echo "$LD_LIBRARY_PATH" > "$SNAP_DATA/nvidia-ctk.ld"
mkdir -p "$SNAP_DATA/etc/cdi" && touch "$SNAP_DATA/etc/cdi/nvidia.yaml"
EOF
  chmod +x "$SNAP/usr/bin/nvidia-ctk"
  snapctl() { :; }
  unset NVIDIA_DRIVER_ROOT
  export LD_LIBRARY_PATH=/snap/lib
  # shellcheck source=../nvidia/lib
  . "$REPO/nvidia/lib"
  HOSTFS="$TMP/hostfs"
}

teardown() {
  rm -rf "$TMP"
}

_libcuda() {
  mkdir -p "$HOSTFS/$1"
  touch "$HOSTFS/$1/libcuda.so.580.0" "$HOSTFS/$1/libnvidia-ml.so.580.0" "$HOSTFS/$1/libc.so.6"
  ln -s libcuda.so.580.0 "$HOSTFS/$1/libcuda.so.1"
  ln -s libnvidia-ml.so.580.0 "$HOSTFS/$1/libnvidia-ml.so.1"
}

_arg() {
  grep -A1 -x -- "$1" "$SNAP_DATA/nvidia-ctk.args" | tail -1
}

_ld_dir() {
  cut -d: -f2 "$SNAP_DATA/nvidia-ctk.ld"
}

@test "lib dirs are probed multiarch, then lib64, then lib" {
  _libcuda usr/lib
  _libcuda usr/lib64
  [ "$(nvidia_host_lib_dir)" = "$HOSTFS/usr/lib64" ]
  _libcuda "usr/lib/$ARCH_TRIPLET"
  [ "$(nvidia_host_lib_dir)" = "$HOSTFS/usr/lib/$ARCH_TRIPLET" ]
}

@test "classic searches the detected dir and puts only its nvidia libs on the loader path" {
  _libcuda usr/lib
  cdi_generate
  [ "$(_arg --library-search-path)" = "$HOSTFS/usr/lib" ]
  dir="$(_ld_dir)"
  [ "$(head -c 9 "$SNAP_DATA/nvidia-ctk.ld")" = /snap/lib ]
  [ "$(readlink "$dir/libnvidia-ml.so.1")" = "$HOSTFS/usr/lib/libnvidia-ml.so.1" ]
  [ -e "$dir/libcuda.so.1" ]
  [ ! -e "$dir/libc.so.6" ]
}

@test "classic drops nvidia libs left over from a previous run" {
  _libcuda usr/lib
  cdi_generate
  [ -L "$(_ld_dir)/libnvidia-ml.so.1" ]
  rm "$HOSTFS/usr/lib/libnvidia-ml.so.580.0" "$HOSTFS/usr/lib/libnvidia-ml.so.1"
  cdi_generate
  [ ! -L "$(_ld_dir)/libnvidia-ml.so.1" ]
}

@test "UC22 keeps the content lib dir on the loader path" {
  mkdir -p "$SNAP/graphics/lib/$ARCH_TRIPLET"
  cdi_generate
  [ "$(_arg --library-search-path)" = "$SNAP/graphics/lib/$ARCH_TRIPLET" ]
  [ "$(_ld_dir)" = "$SNAP/graphics/lib/$ARCH_TRIPLET" ]
}
