#!/usr/bin/env bats
# Tests for install/setup.sh: choosing sections with arguments.
# Every run goes through the dry run. Stub install commands sit first on PATH
# and record any call, so a broken --dry-run fails the test instead of
# installing anything.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_SYSROOT="$BATS_TEST_TMPDIR/sysroot"
  mkdir -p "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT"
  unset HAKPAK_DRY_RUN HAKPAK_DRY_RUN_LOG
  STUBS="$BATS_TEST_TMPDIR/stubs"
  REAL_CALLS="$BATS_TEST_TMPDIR/real-calls.log"
  mkdir -p "$STUBS"
  : > "$REAL_CALLS"
  for c in sudo apt apt-get go pipx gem git curl wget pip pip3 chsh systemctl; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$c" "$REAL_CALLS" > "$STUBS/$c"
    chmod +x "$STUBS/$c"
  done
  export PATH="$STUBS:$PATH"
}

setup_sh() {
  run bash "$REPO/install/setup.sh" "$@" < /dev/null
}

# Section ids setup.sh announced, in order, one per line.
sections_run() {
  grep -oE '^== Section: [a-z]+' <<< "$output" | sed 's/^== Section: //'
}

no_real_calls() {
  if [ -s "$REAL_CALLS" ]; then
    echo "dry run ran real commands:"
    cat "$REAL_CALLS"
    return 1
  fi
}

@test "no section arguments runs every section in install order" {
  setup_sh --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "system environment basic surfing web pentest cloud cicd mitm wordlists rdp" ]
  no_real_calls
  [ -z "$(find "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT" -mindepth 1 -print -quit)" ]
}

@test "named sections run only those" {
  setup_sh web wordlists --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "web wordlists" ]
}

@test "named sections run in install order, each once" {
  setup_sh --dry-run wordlists web wordlists
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "web wordlists" ]
}

@test "unknown section prints the valid sections and exits non-zero" {
  setup_sh web nope --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown section: nope"* ]]
  for s in system environment basic surfing web pentest cloud cicd mitm wordlists rdp; do
    [[ "$output" == *"$s"* ]] || { echo "missing $s in: $output"; return 1; }
  done
  [ -z "$(sections_run)" ]
}

@test "unknown option exits non-zero without running anything" {
  setup_sh --nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option: --nope"* ]]
  [ -z "$(sections_run)" ]
  no_real_calls
}

@test "--dry-run prints what would run and changes nothing" {
  setup_sh --dry-run basic rdp web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"would run: "* ]]
  no_real_calls
  [ -z "$(find "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT" -mindepth 1 -print -quit)" ] || {
    find "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT" -mindepth 1
    return 1
  }
}

@test "--help lists the sections and runs nothing" {
  setup_sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: setup.sh [section...] [--dry-run]"* ]]
  [[ "$output" == *"pentest"* ]]
  [ -z "$(sections_run)" ]
}

@test "a failing section doesn't stop the next, and setup exits non-zero" {
  # A manifest with no wordlists rows: that section fails, web still runs.
  export HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/toolset.txt"
  printf 'web apt only-web\n' > "$HAKPAK_TOOLSET"
  setup_sh --dry-run web wordlists
  [ "$status" -ne 0 ]
  [ "$(sections_run | paste -sd' ')" = "web wordlists" ]
  [[ "$output" == *"Failed sections: wordlists"* ]] || { echo "$output"; return 1; }
}

@test "setup.sh has no Manual mode or interactive menu" {
  run grep -nE 'Manual|select choice' "$REPO/install/setup.sh"
  [ "$status" -ne 0 ]
}

@test "addrep.sh is gone" {
  [ ! -e "$REPO/install/addrep.sh" ]
}
