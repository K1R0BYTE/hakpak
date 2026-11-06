#!/usr/bin/env bats
# Tests for the wsl section (install/wsl.sh): it installs only /etc/wsl.conf,
# and asks before replacing a different one. These use a temp system root
# and a sudo stub that just runs the command, so nothing outside the test
# dir changes.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_SYSROOT="$BATS_TEST_TMPDIR/root"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  mkdir -p "$HOME" "$HAKPAK_SYSROOT/etc" "$HAKPAK_OPT"
  unset HAKPAK_DRY_RUN HAKPAK_DRY_RUN_LOG HAKPAK_WSL_CONF _HAKPAK_PROMPT_TTY
  export HAKPAK_ALLOW_ROOT=1
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexec "$@"\n' > "$BATS_TEST_TMPDIR/bin/sudo"
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  T="$HAKPAK_SYSROOT/etc/wsl.conf"
  OURS="$REPO/configs/wsl.conf"
}

fake_wsl() {
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/kernel"
  echo 6.6.87.2-microsoft-standard-WSL2 > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
}

fake_linux() {
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/kernel"
  echo 6.8.0-45-generic > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
}

wsl_sh() {
  run bash "$REPO/install/wsl.sh" < /dev/null
}

# Run wsl.sh with the given answers typed at its prompt (printf format).
answer() {
  run bash -c 'printf "$1" | _HAKPAK_PROMPT_TTY=1 bash "$2"' _ "$1" "$REPO/install/wsl.sh"
}

@test "wsl is a section, last in install order" {
  source "$REPO/install/lib.sh"
  [ "${HAKPAK_SECTIONS[-1]}" = "wsl:WSL config" ]
}

@test "outside WSL, the wsl section changes nothing" {
  fake_linux
  wsl_sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$T" ]
  [[ "$output" == *"Not WSL"* ]]
}

@test "WSL1 and custom WSL2 kernels count as WSL" {
  source "$REPO/install/lib.sh"
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/kernel" "$HAKPAK_SYSROOT/proc/sys/fs/binfmt_misc"
  echo 4.4.0-19041-Microsoft > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
  is_wsl
  echo 6.6.0-custom > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
  if is_wsl; then return 1; fi
  : > "$HAKPAK_SYSROOT/proc/sys/fs/binfmt_misc/WSLInterop"
  is_wsl
}

@test "with no wsl.conf, it copies hakpak's and says how to apply it" {
  fake_wsl
  wsl_sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp -s "$OURS" "$T"
  [ ! -L "$T" ]
  [ "$(stat -c %a "$T")" = 644 ]
  [ ! -e "$T.bak" ]
  [[ "$output" == *"wsl --shutdown"* ]]
}

@test "the same wsl.conf is not rewritten and asks for no restart" {
  fake_wsl
  cp "$OURS" "$T"
  touch -d '2020-01-01' "$T"
  wsl_sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(stat -c %Y "$T")" = "$(date -d 2020-01-01 +%s)" ]
  [[ "$output" == *"already up to date"* ]]
  [[ "$output" != *"wsl --shutdown"* ]]
  [ ! -e "$T.bak" ]
}

@test "a different wsl.conf: shows the difference and keeps yours without a terminal" {
  fake_wsl
  printf '[boot]\nsystemd=true\n[automount]\nenabled=true\n' > "$T"
  wsl_sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"/etc/wsl.conf (yours)"* ]]
  [[ "$output" == *"configs/wsl.conf (hakpak)"* ]]
  [[ "$output" == *"-enabled=true"* ]]
  [[ "$output" == *"+enabled=false"* ]]
  [ "$(cat "$T")" = "$(printf '[boot]\nsystemd=true\n[automount]\nenabled=true')" ]
  [[ "$output" == *"Kept your /etc/wsl.conf"* ]]
  [[ "$output" == *"HAKPAK_WSL_CONF=replace"* ]]
}

@test "a different wsl.conf with systemd on: recommends keeping yours" {
  fake_wsl
  printf '[boot]\nsystemd=true\n' > "$T"
  wsl_sh
  [[ "$output" == *"Recommended: keep yours"* ]] || { echo "$output"; return 1; }
}

@test "a different wsl.conf without systemd: recommends hakpak's" {
  fake_wsl
  printf '[network]\nhostname=box\n' > "$T"
  wsl_sh
  [[ "$output" == *"Recommended: use hakpak's"* ]] || { echo "$output"; return 1; }
}

@test "answer h: uses hakpak's and backs yours up" {
  fake_wsl
  echo mine > "$T"
  answer 'h\n'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp -s "$OURS" "$T"
  [ "$(cat "$T.bak")" = mine ]
  [[ "$output" == *"wsl --shutdown"* ]]
}

@test "answer k: keeps yours" {
  fake_wsl
  echo mine > "$T"
  answer 'k\n'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$T")" = mine ]
  [ ! -e "$T.bak" ]
}

@test "Enter takes the recommendation; another answer asks again" {
  fake_wsl
  printf '[network]\nhostname=box\n' > "$T"
  answer 'x\n\n'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp -s "$OURS" "$T"
  [ "$(grep -o 'Keep yours (k) or use hakpak' <<< "$output" | wc -l)" -eq 2 ]
}

@test "end of input at the prompt keeps yours" {
  fake_wsl
  echo mine > "$T"
  answer ''
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$T")" = mine ]
}

@test "HAKPAK_WSL_CONF=replace and keep decide without asking" {
  fake_wsl
  echo mine > "$T"
  HAKPAK_WSL_CONF=keep wsl_sh
  [ "$status" -eq 0 ]
  [ "$(cat "$T")" = mine ]
  HAKPAK_WSL_CONF=replace wsl_sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp -s "$OURS" "$T"
  [ "$(cat "$T.bak")" = mine ]
}

@test "HAKPAK_WSL_CONF must be keep or replace" {
  fake_wsl
  echo mine > "$T"
  HAKPAK_WSL_CONF=yes wsl_sh
  [ "$status" -ne 0 ]
  [ "$(cat "$T")" = mine ]
}

@test "dry run records the backup and the copy and changes nothing" {
  fake_wsl
  echo mine > "$T"
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  HAKPAK_WSL_CONF=replace wsl_sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q "cp -p $T $T.bak" "$HAKPAK_DRY_RUN_LOG"
  grep -q "install -m 644 $OURS $T" "$HAKPAK_DRY_RUN_LOG"
  [ "$(cat "$T")" = mine ]
  [ ! -e "$T.bak" ]
}

@test "a failed copy fails the section" {
  fake_wsl
  mkdir -p "$T/x"
  HAKPAK_WSL_CONF=replace wsl_sh
  [ "$status" -ne 0 ]
}
