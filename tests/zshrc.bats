#!/usr/bin/env bats
# Tests for how configs/zsh/.zshrc starts in a bare environment (a container
# or sandbox shell): no locale and no SHELL variable. zsh sources the real
# .zshrc inside a temp home, with a stand-in oh-my-zsh.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  command -v zsh >/dev/null || skip "needs zsh"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset XDG_CONFIG_HOME TMUX STARSHIP_CONFIG LANG LC_ALL LC_CTYPE SHELL
  mkdir -p "$HOME/.oh-my-zsh"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  ln -s "$REPO/configs/zsh/.zshrc" "$HOME/.zshrc"
  ln -s "$REPO/configs/.dircolors" "$HOME/.dircolors"
}

# Source .zshrc in a fresh zsh, then run the given zsh code.
zshrc() {
  run zsh -c "source ~/.zshrc; $1"
}

# --- dircolors ---

@test "zsh starts without a dircolors warning when SHELL is unset" {
  # dircolors gives colors only for a terminal type the file names
  TERM=xterm-256color zshrc 'echo "colors=${LS_COLORS:+set}"'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" != *"dircolors"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"colors=set"* ]] || { echo "$output"; return 1; }
}

@test "zsh starts without a dircolors error when ~/.dircolors is missing" {
  rm "$HOME/.dircolors"
  zshrc 'echo started'
  [[ "$output" != *"dircolors"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"started"* ]]
}

# --- a UTF-8 locale, so tmux draws the prompt glyphs ---

@test "with no locale set, zsh picks a UTF-8 character set" {
  zshrc 'echo "ctype=[$LC_CTYPE] lang=[$LANG] all=[$LC_ALL]"; export -p | grep -c "LC_CTYPE"'
  [[ "$output" == *"ctype=[C.UTF-8] lang=[] all=[]"* ]] || { echo "$output"; return 1; }
  # exported, so tmux started from this shell sees it
  [ "${lines[-1]}" = 1 ]
}

@test "LANG=C or POSIX is not UTF-8 either" {
  for l in C POSIX; do
    LANG="$l" zshrc 'echo "ctype=[$LC_CTYPE] lang=[$LANG]"'
    [[ "$output" == *"ctype=[C.UTF-8] lang=[$l]"* ]] || { echo "$output"; return 1; }
  done
}

@test "a UTF-8 locale you already have is left alone" {
  LANG=en_US.UTF-8 zshrc 'echo "ctype=[$LC_CTYPE] lang=[$LANG]"'
  [[ "$output" == *"ctype=[] lang=[en_US.UTF-8]"* ]] || { echo "$output"; return 1; }
  LANG=C LC_CTYPE=ru_RU.utf8 zshrc 'echo "ctype=[$LC_CTYPE]"'
  [[ "$output" == *"ctype=[ru_RU.utf8]"* ]] || { echo "$output"; return 1; }
}

@test "an explicit LC_ALL is left alone, even when it isn't UTF-8" {
  LC_ALL=C zshrc 'echo "ctype=[$LC_CTYPE] all=[$LC_ALL]"'
  [[ "$output" == *"ctype=[] all=[C]"* ]] || { echo "$output"; return 1; }
}

@test "tmux started from zsh with no locale draws the prompt glyphs, not underscores" {
  command -v tmux >/dev/null || skip "needs tmux"
  command -v script >/dev/null || skip "needs script"
  out="$BATS_TEST_TMPDIR/screen.txt"
  sock="$BATS_TEST_TMPDIR/tmux.sock"
  # A tmux client on a real pseudo-terminal, printing the neon prompt's edge.
  TERM=xterm-256color zsh -c "source ~/.zshrc; script -qec \"tmux -S $sock -f /dev/null new 'printf \\\"\\\\342\\\\226\\\\221\\\\342\\\\226\\\\222\\\\342\\\\226\\\\223 edge\\\\n\\\"; sleep 1'\" $out" >/dev/null 2>&1 || skip "tmux can't start here"
  grep -aq 'edge' "$out" || skip "tmux drew nothing here"
  if grep -aq '___ edge' "$out"; then echo "glyphs became underscores"; return 1; fi
  grep -aq '░▒▓ edge' "$out"
}
