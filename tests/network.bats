#!/usr/bin/env bats
# Tests for the Network section (formerly System): network tools and the NFS
# and SMB clients. Section runs go through the dry run.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  mkdir -p "$HAKPAK_OPT"
  : > "$HAKPAK_DRY_RUN_LOG"
}

lib() {
  # shellcheck source=/dev/null
  source "$REPO/install/lib.sh"
}

@test "network comes right after dev, and there is no system section" {
  lib
  ids="$(for s in "${HAKPAK_SECTIONS[@]}"; do echo "${s%%:*}"; done | paste -sd' ')"
  [[ "$ids " == "top dev network "* ]] || { echo "$ids"; return 1; }
  [[ " $ids " != *" system "* ]] || { echo "$ids"; return 1; }
  run bash "$REPO/install/setup.sh" --help
  [[ "$output" == *"network "*"Network"* ]] || { echo "$output"; return 1; }
}

@test "the network section holds the network tools and the share clients" {
  lib
  [ "$(toolset_rows network | cut -f3 | paste -sd' ')" = "net-tools bind9-dnsutils nfs-common cifs-utils" ]
  [ -z "$(toolset_rows system)" ]
  toolset_check
}

@test "network installs through install/network.sh; install/system.sh is gone" {
  [ -f "$REPO/install/network.sh" ]
  [ ! -e "$REPO/install/system.sh" ]
  run bash "$REPO/install/network.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF "net-tools" "$HAKPAK_DRY_RUN_LOG"
  grep -qF "cifs-utils" "$HAKPAK_DRY_RUN_LOG"
}

@test "setup.sh network runs the network section" {
  run bash "$REPO/install/setup.sh" network --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"== Section: network"* ]] || { echo "$output"; return 1; }
}

@test "setup.sh system fails as an unknown section, with no alias" {
  run bash "$REPO/install/setup.sh" system --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown section: system"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"valid sections: top dev network "* ]] || { echo "$output"; return 1; }
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
}

@test "the README names the network section, not system" {
  grep -q '^Sections: `top`, `dev`, `network`, `environment`,' "$REPO/README.md"
  grep -qx '## Network' "$REPO/README.md"
  ! grep -qx '## System' "$REPO/README.md"
}
