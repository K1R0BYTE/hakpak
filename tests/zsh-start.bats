#!/usr/bin/env bats
# Tests for landing in zsh: the bash hand-over (configs/bash/start-zsh.bash,
# sourced from ~/.bashrc) and the zsh that setup.sh starts when it finishes.
# zsh is a stub that reports how it was started; nothing real is installed.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_SYSROOT="$BATS_TEST_TMPDIR/sysroot"
  mkdir -p "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT" "$BATS_TEST_TMPDIR/bin"
  unset HAKPAK_DRY_RUN HAKPAK_DRY_RUN_LOG HAKPAK_NO_ZSH HAKPAK_ZSH_STARTED
  HOOK="$REPO/configs/bash/start-zsh.bash"
  # A stand-in zsh: says how it was started and what it inherited.
  cat > "$BATS_TEST_TMPDIR/bin/zsh" <<'EOF'
#!/bin/sh
echo "ZSH args=[$*] SHELL=$SHELL started=$HAKPAK_ZSH_STARTED"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/zsh"
  WITH_ZSH="$BATS_TEST_TMPDIR/bin:$PATH"
  # The same PATH without any zsh, whatever the test host has.
  NO_ZSH="$BATS_TEST_TMPDIR/nozsh"
  mkdir -p "$NO_ZSH"
  for c in bash sh cat grep env dirname readlink id getent cut mktemp rm printf mv cp chmod mkdir ls; do
    p="$(command -v "$c")" && ln -sf "$p" "$NO_ZSH/$c"
  done
}

lib() {
  # shellcheck source=/dev/null
  source "$REPO/install/lib.sh"
}

# An interactive bash that reads ~/.bashrc and is then typed `echo still-bash`.
# _HAKPAK_TTY=1 stands in for the terminal a test doesn't have.
interactive_bash() {
  run env PATH="${ZPATH:-$WITH_ZSH}" _HAKPAK_TTY="${TTY:-1}" "$@" bash -i <<< 'echo still-bash; echo "started=[${HAKPAK_ZSH_STARTED:-}] helper=[${_hakpak_zsh:-}]"'
}

hook_in_bashrc() {
  printf '[ -r %q ] && . %q\n' "$HOOK" "$HOOK" > "$HOME/.bashrc"
}

# --- the hand-over hook ---

@test "an interactive bash hands over to zsh" {
  hook_in_bashrc
  interactive_bash
  [[ "$output" == *"ZSH args="* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"still-bash"* ]] || { echo "$output"; return 1; }
}

@test "the zsh it starts knows it is the shell, and is marked as started" {
  hook_in_bashrc
  interactive_bash SHELL=/bin/bash
  [[ "$output" == *"SHELL=$BATS_TEST_TMPDIR/bin/zsh started=1"* ]] || { echo "$output"; return 1; }
}

@test "a bash started from that zsh stays bash" {
  hook_in_bashrc
  interactive_bash HAKPAK_ZSH_STARTED=1
  [[ "$output" == *"still-bash"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"ZSH args="* ]]
}

@test "HAKPAK_NO_ZSH=1 keeps bash" {
  hook_in_bashrc
  interactive_bash HAKPAK_NO_ZSH=1
  [[ "$output" == *"still-bash"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"ZSH args="* ]]
}

@test "without a terminal bash stays bash" {
  hook_in_bashrc
  TTY=0 interactive_bash
  [[ "$output" == *"still-bash"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"ZSH args="* ]]
}

@test "a script or bash -c is never handed over, even if it sources .bashrc" {
  hook_in_bashrc
  run env PATH="$WITH_ZSH" _HAKPAK_TTY=1 bash -c '. "$HOME/.bashrc"; echo still-bash'
  [ "$status" -eq 0 ]
  [ "$output" = "still-bash" ] || { echo "$output"; return 1; }
}

@test "without zsh installed bash stays bash, with no error" {
  hook_in_bashrc
  ZPATH="$NO_ZSH" interactive_bash
  [[ "$output" == *"still-bash"* ]] || { echo "$output"; return 1; }
  ! grep -Ei 'zsh.*(not found|no such file)' <<< "$output" || { echo "$output"; return 1; }
}

@test "a zsh that can't start leaves you in bash, with nothing left behind" {
  hook_in_bashrc
  printf '#!/nonexistent/interpreter\n' > "$BATS_TEST_TMPDIR/bin/zsh"
  interactive_bash
  [[ "$output" == *"still-bash"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"started=[] helper=[]"* ]] || { echo "$output"; return 1; }
}

@test "bash -ic runs its command, it is not swallowed by zsh" {
  hook_in_bashrc
  run env PATH="$WITH_ZSH" _HAKPAK_TTY=1 bash -i -c 'echo still-bash' < /dev/null
  [[ "$output" == *"still-bash"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"ZSH args="* ]] || { echo "$output"; return 1; }
}

@test "a bash started from a zsh that is your login shell stays bash" {
  hook_in_bashrc
  # A parent process named zsh, with no marker in the environment.
  mkdir -p "$BATS_TEST_TMPDIR/parent"
  cp "$(command -v bash)" "$BATS_TEST_TMPDIR/parent/zsh"
  run env PATH="$WITH_ZSH" _HAKPAK_TTY=1 "$BATS_TEST_TMPDIR/parent/zsh" -c 'bash -i <<< "echo still-bash"; true'
  [[ "$output" == *"still-bash"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"ZSH args="* ]] || { echo "$output"; return 1; }
}

@test "the hook leaves no helper variable or changed option behind" {
  hook_in_bashrc
  interactive_bash HAKPAK_NO_ZSH=1
  [[ "$output" == *"started=[] helper=[]"* ]] || { echo "$output"; return 1; }
}

# --- putting the hook into ~/.bashrc ---

@test "start_zsh_from_bash adds one marked line that sources the hook" {
  printf 'alias ll="ls -l"\n' > "$HOME/.bashrc"
  lib
  run start_zsh_from_bash
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(grep -c 'hakpak: start zsh' "$HOME/.bashrc")" -eq 1 ]
  grep -qF "$HOOK" "$HOME/.bashrc"
  grep -qx 'alias ll="ls -l"' "$HOME/.bashrc"
  interactive_bash
  [[ "$output" == *"ZSH args="* ]] || { echo "$output"; return 1; }
}

@test "start_zsh_from_bash makes ~/.bashrc when there is none" {
  lib
  run start_zsh_from_bash
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(grep -c 'hakpak: start zsh' "$HOME/.bashrc")" -eq 1 ]
}

@test "start_zsh_from_bash again changes nothing" {
  lib
  start_zsh_from_bash
  before="$(cat "$HOME/.bashrc"; ls -l --time-style=full-iso "$HOME/.bashrc")"
  run start_zsh_from_bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* ]] || { echo "$output"; return 1; }
  [ "$(cat "$HOME/.bashrc"; ls -l --time-style=full-iso "$HOME/.bashrc")" = "$before" ]
}

@test "start_zsh_from_bash replaces the line of a clone that has moved" {
  printf 'first\n[ -r /old/clone/configs/bash/start-zsh.bash ] && . /old/clone/configs/bash/start-zsh.bash  # hakpak: start zsh\nlast\n' > "$HOME/.bashrc"
  lib
  run start_zsh_from_bash
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(grep -c 'hakpak: start zsh' "$HOME/.bashrc")" -eq 1 ]
  ! grep -q '/old/clone' "$HOME/.bashrc"
  grep -qx first "$HOME/.bashrc"
  grep -qx last "$HOME/.bashrc"
}

@test "start_zsh_from_bash keeps a .bashrc that is a link to your dotfiles a link" {
  mkdir -p "$BATS_TEST_TMPDIR/dotfiles"
  echo '# mine' > "$BATS_TEST_TMPDIR/dotfiles/bashrc"
  ln -s "$BATS_TEST_TMPDIR/dotfiles/bashrc" "$HOME/.bashrc"
  lib
  run start_zsh_from_bash
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -L "$HOME/.bashrc" ]
  grep -q 'hakpak: start zsh' "$BATS_TEST_TMPDIR/dotfiles/bashrc"
  grep -qx '# mine' "$BATS_TEST_TMPDIR/dotfiles/bashrc"
}

@test "a clone path with a space still works from .bashrc" {
  mkdir -p "$BATS_TEST_TMPDIR/my clone"
  cp -r "$REPO/install" "$REPO/configs" "$BATS_TEST_TMPDIR/my clone/"
  # shellcheck source=/dev/null
  source "$BATS_TEST_TMPDIR/my clone/install/lib.sh"
  start_zsh_from_bash
  interactive_bash
  [[ "$output" == *"ZSH args="* ]] || { echo "$output"; return 1; }
}

@test "a .bashrc that can't be replaced is left whole, and the step fails" {
  [ "$(id -u)" -ne 0 ] || skip "root can write anywhere"
  echo '# mine' > "$HOME/.bashrc"
  chmod 555 "$HOME"
  lib
  run start_zsh_from_bash
  chmod 755 "$HOME"
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.bashrc")" = '# mine' ]
}

@test "start_zsh_from_bash keeps the mode of .bashrc and leaves no temp file" {
  echo '# mine' > "$HOME/.bashrc"
  chmod 600 "$HOME/.bashrc"
  lib
  start_zsh_from_bash
  [ "$(stat -c %a "$HOME/.bashrc")" = 600 ]
  [ -z "$(find "$HOME" -name '*.hakpak.*')" ]
}

@test "dry run records the .bashrc change and writes nothing" {
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  lib
  start_zsh_from_bash
  grep -q "$HOME/.bashrc" "$HAKPAK_DRY_RUN_LOG"
  [ ! -e "$HOME/.bashrc" ]
}

@test "basic and top both put the hook in place" {
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  for s in basic.sh top.sh; do
    : > "$HAKPAK_DRY_RUN_LOG"
    run bash "$REPO/install/$s"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    grep -q "_set_marked_line $HOME/.bashrc .*configs/bash/start-zsh.bash" "$HAKPAK_DRY_RUN_LOG" || { echo "$s"; cat "$HAKPAK_DRY_RUN_LOG"; return 1; }
  done
}

# --- zsh at the end of setup.sh ---

# Run start_zsh_now as setup.sh does, as if typed at the prompt of <shell>
# ("" for: not at a prompt, a script started it).
zsh_now() {
  local parent="$1"; shift
  run env PATH="$WITH_ZSH" _HAKPAK_TTY="${TTY:-1}" _HAKPAK_PROMPT_SHELL="$parent" "$@" \
    bash -c 'source "$1/install/lib.sh"; shift; start_zsh_now "$@"; echo "rc=$? no-zsh"' _ "$REPO" ${SECTIONS:-top}
}

@test "after installing top on a terminal, setup starts zsh as a login shell" {
  zsh_now bash
  [[ "$output" == *"ZSH args=[-l] SHELL=$BATS_TEST_TMPDIR/bin/zsh started=1"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"no-zsh"* ]]
}

@test "after installing basic it starts zsh too, after other sections it doesn't" {
  SECTIONS="system basic" zsh_now bash
  [[ "$output" == *"ZSH args="* ]] || { echo "$output"; return 1; }
  SECTIONS="web pentest" zsh_now bash
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
}

@test "setup doesn't start zsh when you already are in zsh" {
  zsh_now zsh
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
  zsh_now bash HAKPAK_ZSH_STARTED=1
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
}

@test "setup doesn't start zsh when a script ran it, even at a terminal" {
  zsh_now ""
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
  # For real: this test is a script, so setup's parent has no prompt.
  run env PATH="$WITH_ZSH" _HAKPAK_TTY=1 bash -c 'source "$1/install/lib.sh"; start_zsh_now top; echo "rc=$? no-zsh"' _ "$REPO"
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
}

@test "_prompt_shell names the shell with job control that started the command" {
  command -v script >/dev/null || skip "needs script(1) for a terminal"
  out="$(script -qec "bash --norc -i" /dev/null <<< "bash -c 'source $REPO/install/lib.sh; echo \"prompt=[\$(_prompt_shell)]\"'; exit" 2>&1)"
  [[ "$out" == *"prompt=[bash]"* ]] || { echo "$out"; return 1; }
}

@test "the zsh setup starts doesn't inherit the installer's own variables" {
  cat > "$BATS_TEST_TMPDIR/bin/zsh" <<'EOF'
#!/bin/sh
[ "$1" = -c ] && exit 0
echo "ZSH root=[${HAKPAK_ROOT:-}] opt=[${HAKPAK_OPT:-}] sysroot=[${HAKPAK_SYSROOT:-}]"
EOF
  zsh_now bash
  [[ "$output" == *"ZSH root=[] opt=[] sysroot=[]"* ]] || { echo "$output"; return 1; }
}

@test "setup doesn't start zsh without a terminal, in a dry run, or with HAKPAK_NO_ZSH=1" {
  TTY=0 zsh_now bash
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
  zsh_now bash HAKPAK_DRY_RUN=1
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
  zsh_now bash HAKPAK_NO_ZSH=1
  [[ "$output" == *"rc=0 no-zsh"* ]] || { echo "$output"; return 1; }
}

@test "setup tells you how to get back and how to switch it off" {
  zsh_now bash
  [[ "$output" == *"exit"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"HAKPAK_NO_ZSH=1"* ]] || { echo "$output"; return 1; }
}

@test "setup.sh starts zsh only after a run with no failed section" {
  s="$REPO/install/setup.sh"
  grep -q '^start_zsh_now "\${selected\[@\]}"$' "$s"
  [ "$(grep -n '^start_zsh_now' "$s" | cut -d: -f1)" -gt "$(grep -n 'Failed sections' "$s" | cut -d: -f1)" ]
  [ "$(grep -n '^start_zsh_now' "$s" | cut -d: -f1)" -eq "$(wc -l < "$s")" ]
}

@test "a dry run on a terminal never starts zsh" {
  run env PATH="$WITH_ZSH" _HAKPAK_TTY=1 _HAKPAK_PROMPT_SHELL=bash bash "$REPO/install/setup.sh" --dry-run top < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" != *"ZSH args="* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"Done: top"* ]]
}

# --- top is the first section ---

@test "top is the first section: in the order, the help, the manifest and the README" {
  lib
  [ "${HAKPAK_SECTIONS[0]}" = "top:Top" ]
  run bash "$REPO/install/setup.sh" --help
  [ "$(grep -E '^  [a-z]+ +[A-Z]' <<< "$output" | head -1 | awk '{ print $1 }')" = top ]
  [ "$(toolset_rows | head -1 | cut -f1)" = top ]
  [ "$(grep -m1 '^## ' <(sed -n '/toolset:start/,/toolset:end/p' "$REPO/README.md"))" = "## Top" ]
  grep -q '^Sections: `top`, `system`, `environment`, `basic`, `surfing`' "$REPO/README.md"
}

@test "top refreshes the package lists itself, before installing anything" {
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  run bash "$REPO/install/top.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sed -n 1p "$HAKPAK_DRY_RUN_LOG")" = "sudo apt-get update" ] || { cat "$HAKPAK_DRY_RUN_LOG"; return 1; }
}
