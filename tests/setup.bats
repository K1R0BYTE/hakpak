#!/usr/bin/env bats
# Tests for install/setup.sh: choosing sections with arguments or the menu.
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

# Run setup.sh with the given keys typed into the menu (printf format).
# _HAKPAK_MENU_TTY=1 lets the menu read the pipe as if it were a terminal.
menu_keys() {
  local keys="$1"; shift
  run bash -c 'printf "$1" | _HAKPAK_MENU_TTY=1 bash "$2" "${@:3}"' _ "$keys" "$REPO/install/setup.sh" "$@"
}

ALL="system environment basic surfing web pentest cloud cicd mitm wordlists rdp"

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

@test "all runs every section in install order" {
  setup_sh all --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "$ALL" ]
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
  [[ "$output" == *"Usage: setup.sh [section...|all] [--dry-run]"* ]]
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

@test "all with other sections still runs every section once" {
  setup_sh --dry-run web all
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "$ALL" ]
}

@test "no section arguments opens the menu with every section unticked" {
  menu_keys 'q' --dry-run
  for s in $ALL; do
    [[ "$output" == *"[ ] $s"* ]] || { echo "missing [ ] $s in: $output"; return 1; }
  done
  [ -z "$(sections_run)" ]
  no_real_calls
}

@test "menu: space ticks, j/k move, Enter installs the ticked sections" {
  # tick system, move down 4 to web, tick, up 2 to basic, tick, Enter
  menu_keys ' jjjj kk \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "system basic web" ]
  [[ "$output" == *"[x] web"* ]]
}

@test "menu: arrow keys move the cursor" {
  menu_keys '\033[B\033[B \033[A \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "environment basic" ]
}

@test "menu: space again unticks" {
  menu_keys '  j \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "environment" ]
}

@test "menu: a ticks every section, a again unticks them" {
  menu_keys 'a\n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "$ALL" ]
  menu_keys 'aaj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "environment" ]
}

@test "menu: the cursor stops at the first and last section" {
  menu_keys 'kkk \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "system" ]
  menu_keys 'jjjjjjjjjjjjjjjjjjjj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "rdp" ]
}

@test "menu: Enter with nothing ticked asks again instead of installing" {
  menu_keys '\nj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Tick at least one section"* ]]
  [ "$(sections_run | paste -sd' ')" = "environment" ]
}

@test "menu: q quits without installing anything" {
  menu_keys ' q' --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Nothing installed"* ]]
  [ -z "$(sections_run)" ]
  no_real_calls
}

@test "menu: end of input quits without installing anything" {
  menu_keys ' j' --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Nothing installed"* ]]
  [ -z "$(sections_run)" ]
  no_real_calls
}

@test "menu: SS3 arrow keys (application cursor mode) move the cursor too" {
  menu_keys '\033OB\033OB \033OA \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "environment basic" ]
}

@test "menu: no line is wider than 79 columns, so redraws don't wrap" {
  menu_keys 'q' --dry-run
  local line
  while IFS= read -r line; do
    [ "${#line}" -lt 80 ] || { echo "too wide (${#line}): $line"; return 1; }
  done < <(grep -E '^(Choose|[> ] \[)' <<< "$output")
}

@test "no sections and no terminal: asks for section names, reads nothing as keys" {
  run bash -c 'printf " \n" | bash "$1" --dry-run' _ "$REPO/install/setup.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"pass section names or all"* ]]
  [[ "$output" != *"[ ] system"* ]]
  [ -z "$(sections_run)" ]
  no_real_calls
}

@test "menu: as root, setup refuses before showing the menu" {
  _HAKPAK_EUID=0 menu_keys 'a\n'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not as root"* ]]
  [[ "$output" != *"[ ] system"* ]]
  no_real_calls
}

@test "--help mentions the menu and all" {
  setup_sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"all"* ]]
  [[ "$output" == *"menu"* ]]
}

@test "setup.sh has no Manual mode" {
  run grep -nE 'Manual|select choice' "$REPO/install/setup.sh"
  [ "$status" -ne 0 ]
}

@test "addrep.sh is gone" {
  [ ! -e "$REPO/install/addrep.sh" ]
}

# --- wsl.conf on WSL, whatever sections are chosen ---

# Pretend to be WSL: the kernel release WSL reports.
fake_wsl() {
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/kernel"
  echo "${1:-6.6.87.2-microsoft-standard-WSL2}" > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
}

fake_linux() {
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/kernel"
  echo "6.8.0-45-generic" > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
}

@test "on WSL, setup copies wsl.conf before the chosen sections, even without rdp" {
  fake_wsl
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  setup_sh --dry-run web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q "install -m 644 $REPO/configs/wsl.conf $HAKPAK_SYSROOT/etc/wsl.conf" "$HAKPAK_DRY_RUN_LOG"
  [ "$(sections_run | paste -sd' ')" = "web" ]
  [[ "$output" == *"wsl --shutdown"* ]] || { echo "$output"; return 1; }
  # before the first section
  [[ "${output%%== Section: web*}" == *"wsl.conf"* ]]
  [ ! -e "$HAKPAK_SYSROOT/etc/wsl.conf" ]
  no_real_calls
}

@test "WSL1 (Microsoft in the kernel release) counts as WSL too" {
  fake_wsl "4.4.0-19041-Microsoft"
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  setup_sh --dry-run web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q "$HAKPAK_SYSROOT/etc/wsl.conf" "$HAKPAK_DRY_RUN_LOG"
}

@test "on WSL, setup backs up an existing wsl.conf before replacing it" {
  fake_wsl
  mkdir -p "$HAKPAK_SYSROOT/etc"
  echo mine > "$HAKPAK_SYSROOT/etc/wsl.conf"
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  setup_sh --dry-run web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q "cp -p $HAKPAK_SYSROOT/etc/wsl.conf $HAKPAK_SYSROOT/etc/wsl.conf.bak" "$HAKPAK_DRY_RUN_LOG"
  # the dry run changed nothing
  [ "$(cat "$HAKPAK_SYSROOT/etc/wsl.conf")" = mine ]
  [ ! -e "$HAKPAK_SYSROOT/etc/wsl.conf.bak" ]
}

@test "not on WSL, setup leaves wsl.conf alone" {
  fake_linux
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  setup_sh --dry-run web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  if grep -q "wsl.conf" "$HAKPAK_DRY_RUN_LOG"; then return 1; fi
  [[ "$output" != *"wsl --shutdown"* ]]
}

@test "WSL with its interop file but a custom kernel counts as WSL too" {
  fake_linux
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/fs/binfmt_misc"
  : > "$HAKPAK_SYSROOT/proc/sys/fs/binfmt_misc/WSLInterop"
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  setup_sh --dry-run web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q "$HAKPAK_SYSROOT/etc/wsl.conf" "$HAKPAK_DRY_RUN_LOG"
}

@test "on WSL, an up-to-date wsl.conf is left alone and asks for no restart" {
  fake_wsl
  mkdir -p "$HAKPAK_SYSROOT/etc"
  cp "$REPO/configs/wsl.conf" "$HAKPAK_SYSROOT/etc/wsl.conf"
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  setup_sh --dry-run web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  if grep -q "wsl.conf" "$HAKPAK_DRY_RUN_LOG"; then return 1; fi
  [[ "$output" == *"already up to date"* ]]
  [[ "$output" != *"wsl --shutdown"* ]]
}

@test "--no-wsl-conf skips wsl.conf on WSL" {
  fake_wsl
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  setup_sh --dry-run --no-wsl-conf web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "web" ]
  if grep -q "wsl.conf" "$HAKPAK_DRY_RUN_LOG"; then return 1; fi
}

@test "--help mentions --no-wsl-conf" {
  setup_sh --help
  [[ "$output" == *"--no-wsl-conf"* ]]
}

@test "on WSL, quitting the menu installs no wsl.conf" {
  fake_wsl
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  menu_keys 'q' --dry-run
  [ "$status" -ne 0 ]
  ! grep -q "wsl.conf" "$HAKPAK_DRY_RUN_LOG"
}

@test "on WSL, a failed wsl.conf copy is reported and setup exits non-zero" {
  fake_wsl
  # a directory where the file should be: cmp fails, install fails
  mkdir -p "$HAKPAK_SYSROOT/etc/wsl.conf/x"
  export HAKPAK_ALLOW_ROOT=1
  # one stubbed apt tool, so the web section runs nothing real
  export HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/toolset.txt"
  printf 'web apt only-web\n' > "$HAKPAK_TOOLSET"
  setup_sh web
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed: /etc/wsl.conf"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"Failed sections: wsl.conf"* ]]
  # the sections still ran
  [ "$(sections_run | paste -sd' ')" = "web" ]
}
