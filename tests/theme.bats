#!/usr/bin/env bats
# Tests for the shell themes: the Starship prompt configs in configs/starship,
# the matching tmux status bars in configs/tmux/themes, the tools/hakpak-theme
# switch, and the Starship install step. The switch runs for real inside a
# temp home; the install goes through the dry run.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  unset XDG_CONFIG_HOME TMUX STARSHIP_CONFIG
  mkdir -p "$HOME" "$HAKPAK_OPT"
  : > "$HAKPAK_DRY_RUN_LOG"
  THEME="$REPO/tools/hakpak-theme"
  STATE="$HOME/.config/hakpak/theme"
  # A tmux stub, so switching never touches a real tmux server.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "tmux $*" >> "%s/tmux.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/tmux"
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

lib() {
  # shellcheck source=/dev/null
  source "$REPO/install/lib.sh"
}

recorded() {
  grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG" || {
    echo "expected command containing: $1"
    echo "--- recorded:"
    cat "$HAKPAK_DRY_RUN_LOG"
    return 1
  }
}

not_recorded() {
  if grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG"; then
    echo "did not expect: $1"
    cat "$HAKPAK_DRY_RUN_LOG"
    return 1
  fi
}

THEMES="neon powerline wireframe"

# True when the file uses a Nerd Font glyph: a private-use character
# (U+E000 to U+F8FF), written raw or as a \uXXXX escape.
uses_nerd_font() {
  grep -qiE '\\u(e[0-9a-f]{3}|f[0-8][0-9a-f]{2})' "$1" && return 0
  LC_ALL=C grep -qP '\xEE[\x80-\xBF]{2}|\xEF[\x80-\xA3][\x80-\xBF]' "$1"
}

# --- the theme files ---

@test "there are three prompt themes: neon, powerline and wireframe" {
  [ "$(cd "$REPO/configs/starship" && ls ./*.toml | sed 's|^\./||; s|\.toml$||' | paste -sd' ')" = "$THEMES" ]
}

@test "every prompt theme has a tmux status bar of the same name" {
  for t in $THEMES; do
    [ -f "$REPO/configs/tmux/themes/$t.conf" ] || { echo "no tmux theme for $t"; return 1; }
  done
  [ "$(cd "$REPO/configs/tmux/themes" && ls | wc -l)" -eq 3 ]
}

@test "every prompt theme is valid TOML with a format and its own palette" {
  command -v python3 >/dev/null || skip "needs python3"
  python3 -c 'import tomllib' 2>/dev/null || skip "needs python 3.11"
  for t in $THEMES; do
    python3 - "$REPO/configs/starship/$t.toml" <<'EOF'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    c = tomllib.load(f)
assert c["format"].strip(), "no format"
assert c["palette"] in c["palettes"], "palette is not defined"
for module in ("username", "hostname", "directory", "git_branch", "git_status", "cmd_duration", "status", "character"):
    assert module in c, "no settings for " + module
    assert "$" + module in c["format"], module + " is not in the format"
assert c["status"]["disabled"] is False, "exit codes are off"
EOF
  done
}

@test "the themes show only what they name: no module comes in through \$all" {
  for t in $THEMES; do
    if grep -qE '\$all([^_a-z]|$)' "$REPO/configs/starship/$t.toml"; then echo "$t uses \$all"; return 1; fi
  done
}

@test "neon and wireframe need no Nerd Font, in the prompt or in tmux" {
  for t in neon wireframe; do
    for f in "$REPO/configs/starship/$t.toml" "$REPO/configs/tmux/themes/$t.conf"; do
      if uses_nerd_font "$f"; then echo "$f uses a Nerd Font glyph"; return 1; fi
    done
  done
}

@test "powerline uses Nerd Font glyphs, and says so at the top" {
  uses_nerd_font "$REPO/configs/starship/powerline.toml"
  head -n 5 "$REPO/configs/starship/powerline.toml" | grep -qi 'nerd font'
}

@test "the themes are purple: each palette has the shared violet and neon" {
  for t in $THEMES; do
    grep -qi "^violet *= *'#7b2cbf'" "$REPO/configs/starship/$t.toml" || { echo "$t"; return 1; }
    grep -qi "^neon *= *'#c77dff'" "$REPO/configs/starship/$t.toml" || { echo "$t"; return 1; }
  done
}

@test "starship renders every theme without a warning" {
  command -v starship >/dev/null || skip "needs starship"
  mkdir -p "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo"
  for t in $THEMES; do
    STARSHIP_CONFIG="$REPO/configs/starship/$t.toml" run starship prompt --status 127 --cmd-duration 14000
    [ "$status" -eq 0 ] || { echo "$t: $output"; return 1; }
    [[ "$output" != *"[WARN]"* && "$output" != *"[ERROR]"* ]] || { echo "$t: $output"; return 1; }
    [[ "$output" == *"127"* ]] || { echo "$t shows no exit code: $output"; return 1; }
    [[ "$output" == *"14s"* ]] || { echo "$t shows no duration: $output"; return 1; }
  done
}

# --- hakpak-theme: which theme is on ---

@test "the default theme is neon" {
  run "$THEME" --path starship
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$REPO/configs/starship/neon.toml" ]
  run "$THEME" --path tmux
  [ "$output" = "$REPO/configs/tmux/themes/neon.conf" ]
  [ ! -e "$HOME/.config" ]
}

@test "hakpak-theme lists the themes and marks the one in use" {
  run "$THEME"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"* neon"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"  powerline"* ]]
  [[ "$output" == *"  wireframe"* ]]
  [ ! -e "$HOME/.config" ]
}

@test "hakpak-theme <name> switches, and the choice is kept outside the repo" {
  before="$(git -C "$REPO" status --porcelain)"
  run "$THEME" wireframe
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$STATE")" = wireframe ]
  run "$THEME" --path starship
  [ "$output" = "$REPO/configs/starship/wireframe.toml" ]
  run "$THEME" --path tmux
  [ "$output" = "$REPO/configs/tmux/themes/wireframe.conf" ]
  run "$THEME"
  [[ "$output" == *"* wireframe"* ]]
  [ "$(git -C "$REPO" status --porcelain)" = "$before" ]
}

@test "the choice goes under XDG_CONFIG_HOME when it is set" {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg"
  "$THEME" powerline
  [ "$(cat "$XDG_CONFIG_HOME/hakpak/theme")" = powerline ]
  [ ! -e "$HOME/.config" ]
}

@test "an unknown theme is refused and changes nothing" {
  "$THEME" wireframe
  run "$THEME" matrix
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown theme: matrix"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"neon"* ]]
  [ "$(cat "$STATE")" = wireframe ]
}

@test "a theme name can't leave the themes directory" {
  for name in ../tmux/.tmux ../../install/lib /etc/passwd 'neon.toml' '' '-x'; do
    run "$THEME" "$name"
    [ "$status" -ne 0 ] || { echo "accepted: $name"; return 1; }
    [ ! -e "$STATE" ]
  done
}

@test "a broken choice file falls back to neon" {
  mkdir -p "$(dirname "$STATE")"
  for bad in '../../../etc/passwd' 'gone-theme' '' 'neon; rm -rf ~' "$(printf 'neon\nwireframe')"; do
    printf '%s\n' "$bad" > "$STATE"
    run "$THEME" --path starship
    [ "$status" -eq 0 ]
    [ "$output" = "$REPO/configs/starship/neon.toml" ] || { echo "$bad -> $output"; return 1; }
  done
}

@test "a theme without a tmux status bar of its own gets the neon one" {
  cp -r "$REPO/tools" "$REPO/configs" "$BATS_TEST_TMPDIR/"
  cp "$BATS_TEST_TMPDIR/configs/starship/neon.toml" "$BATS_TEST_TMPDIR/configs/starship/extra.toml"
  "$BATS_TEST_TMPDIR/tools/hakpak-theme" extra
  run "$BATS_TEST_TMPDIR/tools/hakpak-theme" --path tmux
  [ "$output" = "$BATS_TEST_TMPDIR/configs/tmux/themes/neon.conf" ] || { echo "$output"; return 1; }
  run "$BATS_TEST_TMPDIR/tools/hakpak-theme" --path starship
  [ "$output" = "$BATS_TEST_TMPDIR/configs/starship/extra.toml" ]
}

@test "switching reloads the tmux status bar when a tmux server is running" {
  "$THEME" powerline
  grep -qF "tmux source-file $REPO/configs/tmux/themes/powerline.conf" "$BATS_TEST_TMPDIR/tmux.log"
}

@test "switching works without tmux" {
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/tmux"
  run "$THEME" wireframe
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$STATE")" = wireframe ]
}

@test "hakpak-theme works through a symlink and from any directory" {
  ln -s "$THEME" "$BATS_TEST_TMPDIR/bin/hakpak-theme"
  cd /
  run hakpak-theme --path starship
  [ "$output" = "$REPO/configs/starship/neon.toml" ]
}

@test "hakpak-theme --help names the themes, and a bad option fails" {
  run "$THEME" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"hakpak-theme"*"neon"* ]] || { echo "$output"; return 1; }
  run "$THEME" --path nope
  [ "$status" -ne 0 ]
  run "$THEME" --nope
  [ "$status" -ne 0 ]
}

# --- zsh and tmux pick the theme up ---

@test ".zshrc starts starship with the chosen theme, and keeps agnoster without it" {
  z="$REPO/configs/zsh/.zshrc"
  grep -q 'command -v starship' "$z"
  grep -q 'ZSH_THEME="agnoster"' "$z"
  grep -q 'tools/hakpak-theme" --path starship' "$z"
  grep -q 'starship init zsh' "$z"
  # starship draws the prompt after oh-my-zsh has loaded
  [ "$(grep -n 'starship init zsh' "$z" | cut -d: -f1)" -gt "$(grep -n '^source \$ZSH/oh-my-zsh.sh' "$z" | cut -d: -f1)" ]
}

@test "zsh starts with the neon theme, and hakpak-theme switches it in the same shell" {
  command -v zsh >/dev/null || skip "needs zsh"
  # A stand-in oh-my-zsh and starship: only the theme wiring is under test.
  mkdir -p "$HOME/.oh-my-zsh"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  : > "$HOME/.dircolors"
  printf '#!/bin/sh\necho "HAKPAK_STARSHIP_INIT=1"\n' > "$BATS_TEST_TMPDIR/bin/starship"
  chmod +x "$BATS_TEST_TMPDIR/bin/starship"
  ln -s "$REPO/configs/zsh/.zshrc" "$HOME/.zshrc"
  run zsh -c 'source ~/.zshrc; echo "theme=[$ZSH_THEME] init=$HAKPAK_STARSHIP_INIT"; echo "$STARSHIP_CONFIG"; hakpak-theme wireframe >/dev/null; echo "$STARSHIP_CONFIG"'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"theme=[] init=1"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"$REPO/configs/starship/neon.toml"*"$REPO/configs/starship/wireframe.toml"* ]] || { echo "$output"; return 1; }
}

@test "zsh without starship keeps the agnoster theme" {
  command -v zsh >/dev/null || skip "needs zsh"
  mkdir -p "$HOME/.oh-my-zsh" "$BATS_TEST_TMPDIR/nostarship"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  : > "$HOME/.dircolors"
  ln -s "$REPO/configs/zsh/.zshrc" "$HOME/.zshrc"
  for c in zsh dircolors bash sh dirname readlink cat ls sed env; do
    p="$(command -v "$c")" && ln -s "$p" "$BATS_TEST_TMPDIR/nostarship/$c"
  done
  PATH="$BATS_TEST_TMPDIR/nostarship" run zsh -c 'source ~/.zshrc; echo "theme=[$ZSH_THEME] config=[$STARSHIP_CONFIG]"'
  [[ "$output" == *"theme=[agnoster] config=[]"* ]] || { echo "$output"; return 1; }
}

@test "command highlighting, suggestions and fzf use the purple palette" {
  z="$REPO/configs/zsh/.zshrc"
  grep -q '^ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE=' "$z"
  grep -q "ZSH_HIGHLIGHT_STYLES\[command\]=" "$z"
  grep -q 'FZF_DEFAULT_OPTS=.*--color' "$z"
  grep -qi 'c77dff' "$z"
}

@test ".tmux.conf loads the chosen theme's status bar" {
  c="$REPO/configs/tmux/.tmux.conf"
  grep -q 'hakpak-theme.* --path tmux' "$c"
  # the old orange and green bar is gone
  ! grep -q 'colour214' "$c"
  ! grep -q 'colour112' "$c"
}

@test "every tmux theme styles the bar and keeps the eth0 and tun0 addresses" {
  for t in $THEMES; do
    f="$REPO/configs/tmux/themes/$t.conf"
    grep -q '^set -g status-style ' "$f" || { echo "$t: no status-style"; return 1; }
    grep -q '^set -g status-left ' "$f" || { echo "$t: no status-left"; return 1; }
    grep -q '^set -g status-right .*eth0.*tun0' "$f" || { echo "$t: no addresses"; return 1; }
    grep -q 'window-status-current-format' "$f" || { echo "$t: no current window"; return 1; }
  done
}

@test "tmux loads .tmux.conf and every theme without an error" {
  tmux_bin="$(PATH="${PATH#"$BATS_TEST_TMPDIR/bin:"}" command -v tmux)" || skip "needs tmux"
  sock="$BATS_TEST_TMPDIR/tmux.sock"
  ln -s "$REPO/configs/tmux/.tmux.conf" "$HOME/.tmux.conf"
  # .tmux.conf ends by starting tpm; a stand-in, so that line has something to run.
  mkdir -p "$HOME/.tmux/plugins/tpm"
  printf '#!/bin/sh\n' > "$HOME/.tmux/plugins/tpm/tpm"
  chmod +x "$HOME/.tmux/plugins/tpm/tpm"
  PATH="${PATH#"$BATS_TEST_TMPDIR/bin:"}"
  "$tmux_bin" -S "$sock" -f /dev/null new-session -d -x 120 -y 30 || skip "tmux can't start here"
  for t in $THEMES; do
    run "$tmux_bin" -S "$sock" source-file "$REPO/configs/tmux/themes/$t.conf"
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$t: $output"; "$tmux_bin" -S "$sock" kill-server; return 1; }
  done
  "$THEME" wireframe
  run "$tmux_bin" -S "$sock" source-file "$HOME/.tmux.conf"
  sleep 1
  style="$("$tmux_bin" -S "$sock" show -gv status-style)"
  want="$(sed -n 's/^set -g status-style "\(.*\)"$/\1/p' "$REPO/configs/tmux/themes/wireframe.conf")"
  "$tmux_bin" -S "$sock" kill-server
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$style" = "$want" ] || { echo "status-style is $style, want $want"; return 1; }
}

# --- installing starship ---

@test "starship is in the toolset, right after oh-my-zsh" {
  lib
  toolset_rows | cut -f2-4 | grep -qx "custom	starship	_install_starship"
  names="$(toolset_rows | cut -f3 | paste -sd' ')"
  [[ " $names " == *" oh-my-zsh starship "* ]] || { echo "$names"; return 1; }
}

@test "starship installs from its release, after a checksum check" {
  lib
  has_command() { [ "$1" != starship ] && command -v "$1" >/dev/null 2>&1; }
  uname() { echo x86_64; }
  install_tool custom starship _install_starship
  base=https://github.com/starship/starship/releases/download/v0.0.0
  asset=starship-x86_64-unknown-linux-musl.tar.gz
  recorded "$base/$asset"
  recorded "$base/$asset.sha256"
  recorded "verify_sha256"
  recorded "sudo install -m 755"
  recorded "/usr/local/bin/starship"
  # the check comes before anything is installed
  check="$(grep -n 'verify_sha256' "$HAKPAK_DRY_RUN_LOG" | head -1 | cut -d: -f1)"
  install="$(grep -n 'sudo install' "$HAKPAK_DRY_RUN_LOG" | head -1 | cut -d: -f1)"
  [ "$check" -lt "$install" ]
}

@test "starship on arm64 takes the aarch64 build, and other CPUs fail" {
  lib
  has_command() { [ "$1" != starship ] && command -v "$1" >/dev/null 2>&1; }
  uname() { echo aarch64; }
  install_tool custom starship _install_starship
  recorded "starship-aarch64-unknown-linux-musl.tar.gz"
  : > "$HAKPAK_DRY_RUN_LOG"
  uname() { echo riscv64; }
  run install_tool custom starship _install_starship
  [ "$status" -ne 0 ]
  [[ "$output" == *"riscv64"* ]] || { echo "$output"; return 1; }
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
}

@test "starship already installed is left alone" {
  lib
  has_command() { [ "$1" = starship ] || command -v "$1" >/dev/null 2>&1; }
  run install_tool custom starship _install_starship
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
}

@test "a checksum file with only the hash, or with the asset's name, both check the download" {
  unset HAKPAK_DRY_RUN
  lib
  f="$BATS_TEST_TMPDIR/starship.tar.gz"
  echo data > "$f"
  hash="$(sha256sum "$f" | cut -d' ' -f1)"
  echo "$hash" > "$BATS_TEST_TMPDIR/bare.sha256"
  echo "$hash  starship.tar.gz" > "$BATS_TEST_TMPDIR/named.sha256"
  verify_sha256 "$f" "$BATS_TEST_TMPDIR/bare.sha256" starship.tar.gz
  verify_sha256 "$f" "$BATS_TEST_TMPDIR/named.sha256" starship.tar.gz
  echo tampered > "$f"
  run verify_sha256 "$f" "$BATS_TEST_TMPDIR/bare.sha256" starship.tar.gz
  [ "$status" -ne 0 ]
  # a list for other assets is not a hash for this one
  printf '%s  other.tar.gz\n' "$hash" > "$BATS_TEST_TMPDIR/other.sha256"
  echo data > "$f"
  run verify_sha256 "$f" "$BATS_TEST_TMPDIR/other.sha256" starship.tar.gz
  [ "$status" -ne 0 ]
}

@test "starship is never installed by piping a script into a shell" {
  ! grep -n 'starship.rs/install' "$REPO/install/custom.sh"
}

# --- docs ---

@test "the README shows how to switch themes and what powerline needs" {
  grep -q 'hakpak-theme wireframe' "$REPO/README.md"
  grep -q 'Nerd Font' "$REPO/README.md"
  grep -q '^\* starship: ' "$REPO/README.md"
}
