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
  for c in sudo apt apt-get go pipx gem git curl wget pip pip3 chsh usermod systemctl; do
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

ALL="system environment basic surfing web pentest cloud cicd mitm wordlists wsl rdp"

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
  for s in system environment basic surfing web pentest cloud cicd mitm wordlists wsl rdp; do
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
  done < <(grep -E '^(Arrows|[> ] \[|      )' <<< "$output")
}

@test "menu: a section line shows the section id once, without its title" {
  menu_keys 'q' --dry-run
  [[ "$output" == *"> [ ] system"$'\n'* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"  [ ] web"$'\n'* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"Web Tools"* ]] || { echo "$output"; return 1; }
}

@test "menu: under each section it lists that section's tools from the manifest" {
  menu_keys 'q' --dry-run
  # The tools printed between one section line and the next.
  section_tools() {
    awk -v id="$1" '
      /^[> ] \[.\] / { l = substr($0, 7); split(l, f, " "); on = (f[1] == id); next }
      on && /^      / { for (i = 1; i <= NF; i++) print $i }
      on && !/^      / { on = 0 }
    ' <<< "$output"
  }
  source "$REPO/install/lib.sh"
  for s in $ALL; do
    want="$(toolset_rows "$s" | cut -f3 | paste -sd' ')"
    [ "$s" = wsl ] && want=/etc/wsl.conf  # config only, no tools
    got="$(section_tools "$s" | paste -sd' ')"
    [ "$got" = "$want" ] || { echo "$s: want '$want', got '$got'"; return 1; }
  done
}

@test "menu: a tool added to the manifest shows up in the menu" {
  cp "$REPO/install/toolset.txt" "$BATS_TEST_TMPDIR/toolset.txt"
  echo "rdp  apt  zz-new-tool" >> "$BATS_TEST_TMPDIR/toolset.txt"
  HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/toolset.txt" menu_keys 'q' --dry-run
  [[ "$output" == *"zz-new-tool"* ]] || { echo "$output"; return 1; }
}

@test "menu: redraws move up over the whole frame, tool lines included" {
  # _HAKPAK_MENU_REDRAW=1 redraws as on a terminal. One key: two frames,
  # with a cursor-up of exactly the first frame's height between them.
  run bash -c 'printf "j" | _HAKPAK_MENU_TTY=1 _HAKPAK_MENU_REDRAW=1 bash "$1" --dry-run' _ "$REPO/install/setup.sh"
  up="$(grep -aoE $'\033\\[[0-9]+A' <<< "$output" | tr -dc 0-9)"
  [ -n "$up" ] || { echo "no redraw in: $output"; return 1; }
  frame="$(sed -n '/^Arrows or j\/k move/,$p' <<< "$output" | sed $'/\033\\[/,$d' | wc -l)"
  [ "$up" -eq "$frame" ] || { echo "moves up $up, frame is $frame lines"; return 1; }
}

@test "menu: tool lines wrap to a terminal narrower than 80 columns" {
  COLUMNS=50 menu_keys 'q' --dry-run
  local line
  while IFS= read -r line; do
    [ "${#line}" -lt 50 ] || { echo "too wide (${#line}): $line"; return 1; }
  done < <(grep -E '^      ' <<< "$output")
  [[ "$output" == *"gowitness"* ]]
}

@test "menu: on a short terminal only the section under the cursor lists its tools" {
  LINES=20 menu_keys 'jq' --dry-run
  first="$(sed -n '/^Arrows or j\/k move/,/^Arrows or j\/k move/p' <<< "$output")"
  [[ "$first" == *"build-essential"* ]] || { echo "$first"; return 1; }
  [[ "$first" != *"python3-pip"* ]] || { echo "$first"; return 1; }
  second="$(sed -n '1,/^Arrows or j\/k move/!p' <<< "$output" | sed -n '/^Arrows or j\/k move/,$p')"
  [[ "$second" == *"python3-pip"* ]] || { echo "$second"; return 1; }
  [[ "$second" != *"build-essential"* ]] || { echo "$second"; return 1; }
}

@test "menu: on a short terminal, a frame still fits and redraws over the last one" {
  run bash -c 'printf "jj" | LINES=20 _HAKPAK_MENU_TTY=1 _HAKPAK_MENU_REDRAW=1 bash "$1" --dry-run' _ "$REPO/install/setup.sh"
  ups="$(grep -aoE $'\033\\[[0-9]+A' <<< "$output" | tr -dc '0-9\n')"
  [ "$(wc -l <<< "$ups")" -eq 2 ] || { echo "redraws: $ups"; return 1; }
  # frames, split at each redraw
  frames="$(sed -n '/^Arrows or j\/k move/,$p' <<< "$output" | sed $'s/\033\\[[0-9]*A\033\\[J/=REDRAW=\\\n/')"
  f1="$(awk '/^=REDRAW=$/{exit} {n++} END{print n}' <<< "$frames")"
  f2="$(awk '/^=REDRAW=$/{c++; next} c==1{n++} END{print n}' <<< "$frames")"
  [ "$(sed -n 1p <<< "$ups")" -eq "$f1" ] || { echo "up $(sed -n 1p <<< "$ups") vs frame $f1"; return 1; }
  [ "$(sed -n 2p <<< "$ups")" -eq "$f2" ] || { echo "up $(sed -n 2p <<< "$ups") vs frame $f2"; return 1; }
  [ "$f1" -lt 20 ] && [ "$f2" -lt 20 ]
}

@test "menu: an unreadable manifest is reported once, not once per section" {
  HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/missing.txt" menu_keys 'q' --dry-run
  [ "$(grep -c "can't read" <<< "$output")" -eq 1 ] || { echo "$output"; return 1; }
  [[ "$output" == *"[ ] system"* ]]
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


# --- the wsl section in the menu ---

fake_wsl() {
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/kernel"
  echo 6.6.87.2-microsoft-standard-WSL2 > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
}

@test "menu: on WSL, the wsl section starts ticked" {
  fake_wsl
  menu_keys 'q' --dry-run
  [[ "$output" == *"[x] wsl"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"[ ] rdp"* ]]
}

@test "menu: on WSL, Enter right away installs only the wsl section" {
  fake_wsl
  menu_keys '\n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "wsl" ]
}

@test "menu: outside WSL, the wsl section starts unticked" {
  menu_keys 'q' --dry-run
  [[ "$output" == *"[ ] wsl"* ]] || { echo "$output"; return 1; }
}

@test "setup installs wsl.conf only when the wsl section is chosen" {
  fake_wsl
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  setup_sh --dry-run web
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  if grep -q "wsl.conf" "$HAKPAK_DRY_RUN_LOG"; then return 1; fi
  setup_sh --dry-run wsl
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q "install -m 644 $REPO/configs/wsl.conf $HAKPAK_SYSROOT/etc/wsl.conf" "$HAKPAK_DRY_RUN_LOG"
}

@test "menu: the wsl section lists the file it installs, like the tool lists" {
  menu_keys 'q' --dry-run
  grep -A1 -E '^. \[.\] wsl$' <<< "$output" | grep -qx '      /etc/wsl.conf' || { echo "$output"; return 1; }
}
