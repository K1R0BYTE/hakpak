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

ALL="top dev ai network environment basic surfing web pentest cloud cicd mitm wordlists wsl rdp"

# Every section but ai: with all of them ticked, ai's tools come with dev.
ALL_RUN="top dev network environment basic surfing web pentest cloud cicd mitm wordlists wsl rdp"

# The last menu frame setup.sh drew.
last_frame() {
  awk '/^Arrows or j\/k move/ { buf = "" } { buf = buf $0 "\n" } /^== Section: / { exit } END { printf "%s", buf }' <<< "$output" |
    sed '/^Section .*: nothing/,$d'
}

# The tool rows of the last frame: "<box> <name>", one per line.
tool_rows() {
  last_frame | grep -E '^    [> ] \[.\] ' | sed -E 's/^    . (\[.\]) ([^ ]+).*/\1 \2/'
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

@test "all runs every section in install order" {
  setup_sh all --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "$ALL_RUN" ]
  [[ "$output" == *"Section ai: its tools come with top dev"* ]] || { echo "$output"; return 1; }
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
  for s in $ALL; do
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
  [ "$(sections_run | paste -sd' ')" = "$ALL_RUN" ]
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
  # tick top, move down 7 to web, tick, up 2 to basic, tick, Enter
  menu_keys ' jjjjjjj kk \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "top basic web" ]
  [[ "$output" == *"[x] web"* ]]
}

@test "menu: arrow keys move the cursor" {
  menu_keys '\033[B\033[B\033[B\033[B \033[A \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "network environment" ]
}

@test "menu: space again unticks" {
  menu_keys '  jjj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "network" ]
}

@test "menu: a ticks every section, a again unticks them" {
  menu_keys 'a\n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "$ALL_RUN" ]
  menu_keys 'aajjj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "network" ]
}

@test "menu: the cursor stops at the first and last section" {
  menu_keys 'kkk \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "top" ]
  menu_keys 'jjjjjjjjjjjjjjjjjjjj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "rdp" ]
}

@test "menu: Enter with nothing ticked asks again instead of installing" {
  menu_keys '\njjj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Tick at least one section"* ]]
  [ "$(sections_run | paste -sd' ')" = "network" ]
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
  menu_keys '\033OB\033OB\033OB\033OB \033OA \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "network environment" ]
}

@test "menu: no line is wider than 79 columns, so redraws don't wrap" {
  menu_keys 'q' --dry-run
  local line
  while IFS= read -r line; do
    [ "${#line}" -lt 80 ] || { echo "too wide (${#line}): $line"; return 1; }
  done < <(grep -E '^(Arrows|[> ] \[|      )' <<< "$output")
}

@test "menu: a section line shows the section id once, without its title, and how many tools are ticked" {
  menu_keys 'q' --dry-run
  grep -qE '^> \[ \] top +0/8$' <<< "$output" || { echo "$output"; return 1; }
  grep -qE '^  \[ \] web +0/12$' <<< "$output" || { echo "$output"; return 1; }
  [[ "$output" != *"Web Tools"* ]] || { echo "$output"; return 1; }
}

@test "menu: opening a section lists its tools from the manifest, one checkbox each" {
  source "$REPO/install/lib.sh"
  local i=0 k keys s want got
  for s in $ALL; do
    keys=""
    for ((k = 0; k < i; k++)); do keys="${keys}j"; done
    i=$((i + 1))
    [ "$s" = wsl ] && continue  # config only, no tools
    menu_keys "${keys}lq" --dry-run
    want="$(toolset_rows "$s" | cut -f3 | paste -sd' ')"
    got="$(tool_rows | awk '{ print $NF }' | paste -sd' ')"
    [ "$got" = "$want" ] || { echo "$s: want '$want', got '$got'"; return 1; }
  done
}

@test "menu: a tool added to the manifest shows up in the menu" {
  cp "$REPO/install/toolset.txt" "$BATS_TEST_TMPDIR/toolset.txt"
  echo "rdp  apt  zz-new-tool" >> "$BATS_TEST_TMPDIR/toolset.txt"
  HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/toolset.txt" menu_keys 'jjjjjjjjjjjjjjjjjjjjlq' --dry-run
  tool_rows | grep -qx '\[ \] zz-new-tool' || { echo "$output"; return 1; }
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
  COLUMNS=50 menu_keys 'jjjjjjjq' --dry-run
  local line
  while IFS= read -r line; do
    [ "${#line}" -lt 50 ] || { echo "too wide (${#line}): $line"; return 1; }
  done < <(grep -E '^      ' <<< "$output")
  [[ "$output" == *"gowitness"* ]]
  # tool rows with their notes are cut to the width too
  COLUMNS=50 menu_keys 'jlq' --dry-run
  while IFS= read -r line; do
    [ "${#line}" -lt 50 ] || { echo "too wide (${#line}): $line"; return 1; }
  done < <(grep -E '^    [> ] \[' <<< "$output")
  [[ "$output" == *"claude-code-config"* ]]
}

@test "menu: only the section under the cursor lists its tools" {
  menu_keys 'jq' --dry-run
  first="$(sed -n '/^Arrows or j\/k move/,/^Arrows or j\/k move/p' <<< "$output")"
  [[ "$first" == *"claude-code"* ]] || { echo "$first"; return 1; }
  [[ "$first" != *"build-essential"* ]] || { echo "$first"; return 1; }
  second="$(last_frame)"
  [[ "$second" == *"build-essential"* ]] || { echo "$second"; return 1; }
  [[ "$second" != *"oh-my-zsh"* ]] || { echo "$second"; return 1; }
}

@test "menu: on a short terminal a tool list longer than the room left is cut" {
  LINES=21 menu_keys 'jq' --dry-run
  second="$(last_frame)"
  [ "$(grep -c '^      ' <<< "$second")" -eq 2 ] || { echo "$second"; return 1; }
  grep -qx '      \.\.\.' <<< "$second"
  # with room for all of it, nothing is cut
  LINES=31 menu_keys 'jq' --dry-run
  [[ "$output" != *"      ..."* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"claude-code-config"* ]]
}

@test "menu: on a short terminal an open section scrolls to keep the cursor in view" {
  # 15 sections leave 24 - 15 - 4 = 5 rows for dev's 31 tools.
  LINES=24 menu_keys "jl$(printf 'j%.0s' $(seq 1 25))q" --dry-run
  frame="$(last_frame)"
  [ "$(tool_rows | wc -l)" -eq 5 ] || { echo "$frame"; return 1; }
  # the 26th tool of dev is under the cursor
  grep -qE '^    > \[ \] git-cleanup' <<< "$frame" || { echo "$frame"; return 1; }
  # the frame, and the "Nothing installed" after it
  [ "$(wc -l <<< "$frame")" -le 24 ]
}

@test "menu: on a short terminal, a frame still fits and redraws over the last one" {
  run bash -c 'printf "jjl" | LINES=21 _HAKPAK_MENU_TTY=1 _HAKPAK_MENU_REDRAW=1 bash "$1" --dry-run' _ "$REPO/install/setup.sh"
  ups="$(grep -aoE $'\033\\[[0-9]+A' <<< "$output" | tr -dc '0-9\n')"
  [ "$(wc -l <<< "$ups")" -eq 3 ] || { echo "redraws: $ups"; return 1; }
  frames="$(sed -n '/^Arrows or j\/k move/,$p' <<< "$output" | sed $'s/\033\\[[0-9]*A\033\\[J/=REDRAW=\\\n/')"
  for k in 1 2 3; do
    f="$(awk -v k="$k" '/^=REDRAW=$/{c++; next} c==k-1{n++} END{print n}' <<< "$frames")"
    [ "$(sed -n "${k}p" <<< "$ups")" -eq "$f" ] || { echo "frame $k: up $(sed -n "${k}p" <<< "$ups") vs $f"; return 1; }
    [ "$f" -lt 21 ] || { echo "frame $k is $f lines"; return 1; }
  done
}

@test "menu: an unreadable manifest is reported once, not once per section" {
  HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/missing.txt" menu_keys 'q' --dry-run
  [ "$(grep -c "can't read" <<< "$output")" -eq 1 ] || { echo "$output"; return 1; }
  [[ "$output" == *"[ ] network"* ]]
}

@test "no sections and no terminal: asks for section names, reads nothing as keys" {
  run bash -c 'printf " \n" | bash "$1" --dry-run' _ "$REPO/install/setup.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"pass section names or all"* ]]
  [[ "$output" != *"[ ] network"* ]]
  [ -z "$(sections_run)" ]
  no_real_calls
}

@test "menu: as root, setup refuses before showing the menu" {
  _HAKPAK_EUID=0 menu_keys 'a\n'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not as root"* ]]
  [[ "$output" != *"[ ] network"* ]]
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
  menu_keys 'jjjjjjjjjjjjjq' --dry-run
  grep -A1 -E '^. \[.\] wsl$' <<< "$output" | grep -qx '      /etc/wsl.conf' || { echo "$output"; return 1; }
}


# --- picking single tools ---

@test "menu: ticking a section ticks every tool in it" {
  menu_keys ' lq' --dry-run
  grep -qE '^> \[x\] top +8/8$|^  \[x\] top +8/8$' <<< "$(last_frame)" || { last_frame; return 1; }
  [ "$(tool_rows | cut -d' ' -f1 | sort -u)" = "[x]" ] || { tool_rows; return 1; }
}

@test "menu: l opens a section, space unticks one tool, and the section shows [~]" {
  menu_keys ' l q' --dry-run
  frame="$(last_frame)"
  grep -qE '^  \[~\] top +7/8$' <<< "$frame" || { echo "$frame"; return 1; }
  grep -qE '^    > \[ \] vim' <<< "$frame" || { echo "$frame"; return 1; }
}

@test "menu: only the ticked tools of a section are installed" {
  menu_keys ' l \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "top" ]
  [[ "$output" == *"Installing fzf zsh tmux"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"Installing vim"* ]] || { echo "$output"; return 1; }
}

@test "menu: a tool shared by several sections is ticked in all of them" {
  menu_keys ' jlq' --dry-run
  frame="$(last_frame)"
  grep -qE '^  \[~\] dev +1/31$|^> \[~\] dev +1/31$' <<< "$frame" || { echo "$frame"; return 1; }
  grep -qE '^  \[~\] ai +1/11$' <<< "$frame" || { echo "$frame"; return 1; }
  grep -qE '^  \[~\] basic +7/14$' <<< "$frame" || { echo "$frame"; return 1; }
  [ "$(tool_rows | grep -c '^\[x\]')" -eq 1 ]
  tool_rows | grep -qx '\[x\] claude-code'
}

@test "menu: unticking a shared tool in one section unticks it everywhere" {
  # tick top, open dev, go down to claude-code (its 21st tool), untick it
  menu_keys " jl$(printf 'j%.0s' $(seq 1 20)) q" --dry-run
  frame="$(last_frame)"
  grep -qE '^    > \[ \] claude-code ' <<< "$frame" || { echo "$frame"; return 1; }
  grep -qE '^  \[~\] top +7/8$' <<< "$frame" || { echo "$frame"; return 1; }
  grep -qE '^  \[ \] ai +0/11$' <<< "$frame" || { echo "$frame"; return 1; }
}

@test "menu: a shared tool is installed once, with the section that has the most of its tools ticked" {
  menu_keys ' \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "top" ]
  # tick top and all of ai: claude-code comes with top, the rest with ai
  menu_keys ' jj \n' --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "top ai" ]
  [ "$(grep -cE 'Installing claude-code([^-a-z]|$)' <<< "$output")" -eq 1 ] || { echo "$output"; return 1; }
}

@test "menu: h closes the open section and goes back to its row" {
  menu_keys ' ljhq' --dry-run
  frame="$(last_frame)"
  grep -qE '^> \[x\] top' <<< "$frame" || { echo "$frame"; return 1; }
  [ -z "$(tool_rows)" ] || { echo "$frame"; return 1; }
}

@test "menu: space on a partly ticked section ticks all of it" {
  menu_keys ' l h q' --dry-run
  grep -qE '^> \[x\] top +8/8$' <<< "$(last_frame)" || { last_frame; return 1; }
}

@test "menu: past the last tool the cursor goes on to the next section and closes the open one" {
  menu_keys "l$(printf 'j%.0s' $(seq 1 8))q" --dry-run
  frame="$(last_frame)"
  grep -qE '^> \[ \] dev' <<< "$frame" || { echo "$frame"; return 1; }
  [ -z "$(tool_rows)" ] || { echo "$frame"; return 1; }
}

@test "menu: k from the first tool goes back to the section row, still open" {
  menu_keys 'lkq' --dry-run
  frame="$(last_frame)"
  grep -qE '^> \[ \] top' <<< "$frame" || { echo "$frame"; return 1; }
  [ "$(tool_rows | wc -l)" -eq 8 ] || { echo "$frame"; return 1; }
}

@test "menu: right and left arrows open and close a section" {
  menu_keys '\033[Cq' --dry-run
  [ "$(tool_rows | wc -l)" -eq 8 ] || { last_frame; return 1; }
  menu_keys '\033[C\033[Dq' --dry-run
  [ -z "$(tool_rows)" ] || { last_frame; return 1; }
}

@test "menu: a tool row shows the tool's note" {
  menu_keys 'lq' --dry-run
  grep -qE '^    [> ] \[ \] fzf +Ctrl\+R history search$' <<< "$(last_frame)" || { last_frame; return 1; }
}

@test "named sections install every tool of each, a shared tool once" {
  setup_sh --dry-run dev ai
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sections_run | paste -sd' ')" = "dev" ]
  [[ "$output" == *"Section ai: its tools come with dev"* ]] || { echo "$output"; return 1; }
  setup_sh --dry-run top ai
  [ "$(sections_run | paste -sd' ')" = "top ai" ]
  [ "$(grep -cE 'Installing claude-code([^-a-z]|$)' <<< "$output")" -eq 1 ] || { echo "$output"; return 1; }
  setup_sh --dry-run ai
  [ "$(sections_run | paste -sd' ')" = "ai" ]
}
