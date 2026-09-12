#!/usr/bin/env bats
# Tests for spread-matrix. Run with: bats .github/scripts/spread-matrix/

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/spread-matrix"
  # Canned spread -list output: the full 23-system board, two tasks each.
  local systems=(
    ubuntu-core-22.amd64
    ubuntu-core-22.arm64
    ubuntu-cloud-22.04.amd64
    ubuntu-cloud-22.04.arm64
    ubuntu-core-24.amd64
    ubuntu-core-24.arm64
    ubuntu-cloud-24.04.amd64
    ubuntu-cloud-24.04.arm64
    ubuntu-cloud-24.04.riscv64
    ubuntu-cloud-24.04.s390x
    ubuntu-cloud-24.04.ppc64el
    ubuntu-core-26.amd64
    ubuntu-core-26.arm64
    ubuntu-cloud-26.04.amd64
    ubuntu-cloud-26.04.arm64
    ubuntu-cloud-26.04.riscv64
    ubuntu-cloud-26.04.s390x
    ubuntu-cloud-26.04.ppc64el
    ubuntu-cloud-26.10.amd64
    ubuntu-cloud-26.10.arm64
    ubuntu-cloud-26.10.riscv64
    ubuntu-cloud-26.10.s390x
    ubuntu-cloud-26.10.ppc64el
  )
  JOBS=""
  local s t
  for s in "${systems[@]}"; do
    for t in build hello-world; do
      JOBS+="garden:${s}:spread/main/${t}"$'\n'
    done
  done
}

# The include-matrix for a filter, stderr diagnostics dropped.
matrix() {
  "$SCRIPT" "$1" <<<"$JOBS" 2>/dev/null
}

# The selected system names for a filter, one per line, matrix order.
systems() {
  matrix "$1" | jq -r '.include[].system'
}

@test "empty filter selects every system with every task" {
  [ "$(matrix '' | jq '.include | length')" -eq 23 ]
  [ "$(matrix '' | jq -r '.include[].jobs' | grep -c 'build.*hello-world')" -eq 23 ]
}

@test "systems are sorted newest release first" {
  [ "$(systems '' | sed -n 1p)" = ubuntu-cloud-26.10.amd64 ]
  [ "$(systems '' | sed -n 6p)" = ubuntu-cloud-26.04.amd64 ]
  [ "$(systems '' | sed -n 11p)" = ubuntu-core-26.amd64 ]
  [ "$(systems '' | sed -n 23p)" = ubuntu-core-22.arm64 ]
}

@test "architecture term" {
  [ "$(systems 'amd64' | grep -vc amd64)" -eq 0 ]
  [ "$(systems 'amd64' | wc -l)" -eq 7 ]
}

@test "alternatives within a term" {
  [ "$(systems 'ppc64el|riscv64' | grep -Evc 'ppc64el|riscv64')" -eq 0 ]
  [ "$(systems 'ppc64el|riscv64' | wc -l)" -eq 6 ]
}

@test "chained terms narrow" {
  [ "$(systems 'core !22' | tr '\n' ' ')" = "ubuntu-core-26.amd64 ubuntu-core-26.arm64 ubuntu-core-24.amd64 ubuntu-core-24.arm64 " ]
}

@test "LTS term selects its paired core release" {
  [ "$(systems '26.04' | grep -c 'core-26\.')" -eq 2 ]
  [ "$(systems '26.04' | wc -l)" -eq 7 ]
}

@test "negated LTS term drops its paired core release" {
  [ "$(systems '!26.04' | grep -c 'core-26\.')" -eq 0 ]
  [ "$(systems '!26.04' | wc -l)" -eq 16 ]
}

@test "development series term leaves core alone" {
  [ "$(systems '26.10' | grep -vc 'cloud-26\.10')" -eq 0 ]
  [ "$(systems '26.10' | wc -l)" -eq 5 ]
}

@test "literal core system name still matches" {
  [ "$(systems 'core-26' | wc -l)" -eq 2 ]
}

@test "task term selects a task subset on every system" {
  [ "$(matrix 'build' | jq '.include | length')" -eq 23 ]
  [ "$(matrix 'build' | jq -r '.include[].jobs' | grep -c hello-world)" -eq 0 ]
}

@test "combined system and task filter" {
  [ "$(matrix '!26.04 cloud amd64 build' | jq -c '[.include[] | .jobs]')" = \
    '["garden:ubuntu-cloud-26.10.amd64:spread/main/build","garden:ubuntu-cloud-24.04.amd64:spread/main/build","garden:ubuntu-cloud-22.04.amd64:spread/main/build"]' ]
}

@test "multiple tasks for one system stay on one matrix entry" {
  [ "$(matrix 'cloud-24.04.amd64' | jq -r '.include[0].jobs')" = \
    "garden:ubuntu-cloud-24.04.amd64:spread/main/build garden:ubuntu-cloud-24.04.amd64:spread/main/hello-world" ]
}

@test "zero-match filter fails loudly" {
  run "$SCRIPT" 'no-such-thing' <<<"$JOBS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"selected no jobs"* ]]
}
