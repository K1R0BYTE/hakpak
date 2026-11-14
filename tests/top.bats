#!/usr/bin/env bats
# Tests for the Top section: the everyday shell tools (vim, fzf, zsh,
# oh-my-zsh, tmux) and the Claude Code CLI with the skills kept in
# .claude/skills. Section runs go through the dry run; the skill links and the
# key fingerprint check use the real adapter inside a temp home.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_SYSROOT="$BATS_TEST_TMPDIR/sysroot"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  unset CLAUDE_CONFIG_DIR
  mkdir -p "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT"
  : > "$HAKPAK_DRY_RUN_LOG"
  SKILLS="$HOME/.claude/skills"
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

section() {
  grep -q 'lib.sh' "$REPO/install/$1" || { echo "$1 does not source lib.sh"; return 1; }
  run bash "$REPO/install/$1"
}

# Stub commands on PATH for real-adapter tests: stub <name> <script body>
stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Load the install module as if `claude` were (1) or weren't (0) installed,
# so a test doesn't depend on what the test host has.
lib_with_claude() {
  lib
  if [ "$1" = 1 ]; then
    has_command() { [ "$1" = claude ] || command -v "$1" >/dev/null 2>&1; }
  else
    has_command() { [ "$1" != claude ] && command -v "$1" >/dev/null 2>&1; }
  fi
}

# A throwaway OpenPGP key, exported armored to $KEY; its fingerprint in $FPR.
make_test_key() {
  local home="$BATS_TEST_TMPDIR/gnupg-src"
  mkdir -p -m 700 "$home"
  gpg --batch --homedir "$home" --quick-gen-key --passphrase '' 'hakpak test <t@example.test>' default default never 2>/dev/null ||
    skip "gpg can't make a test key here"
  KEY="$BATS_TEST_TMPDIR/vendor.asc"
  gpg --batch --homedir "$home" --armor --export > "$KEY"
  FPR="$(gpg --batch --homedir "$home" --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
}

CLAUDE_KEY_URL=https://downloads.claude.ai/keys/claude-code.asc
CLAUDE_LINE='deb [signed-by=/etc/apt/keyrings/claude-code.gpg] https://downloads.claude.ai/claude-code/apt/stable stable main'
CLAUDE_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# --- the section in the manifest ---

@test "top section lists vim, fzf, zsh, oh-my-zsh, tmux, tpm and claude-code" {
  lib
  [ "$(toolset_rows top | cut -f3 | paste -sd' ')" = "vim fzf zsh oh-my-zsh tmux tpm claude-code" ]
}

@test "basic section keeps only the tools that didn't move to top" {
  lib
  [ "$(toolset_rows basic | cut -f3 | paste -sd' ')" = "git wget curl zip unzip p7zip-full xclip" ]
}

@test "top comes right after basic, which installs the git and curl it needs" {
  lib
  ids="$(for s in "${HAKPAK_SECTIONS[@]}"; do echo "${s%%:*}"; done | paste -sd' ')"
  [[ " $ids " == *" basic top "* ]] || { echo "$ids"; return 1; }
  run bash "$REPO/install/setup.sh" --help
  [[ "$output" == *"top "*"Top"* ]] || { echo "$output"; return 1; }
}

@test "the README names the top section and lists its tools" {
  grep -q '^Sections: .*`basic`, `top`, `surfing`' "$REPO/README.md"
  grep -qx '## Top' "$REPO/README.md"
  grep -q '^\* claude-code: ' "$REPO/README.md"
}

# --- the section script ---

@test "top section runs cleanly in dry run" {
  section top.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$(find "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT" -mindepth 1 -print -quit)" ]
}

@test "top section installs its apt tools in one call" {
  section top.sh
  recorded "apt-get install -y vim fzf zsh tmux"
}

@test "top section installs oh-my-zsh by git clone, then its plugins" {
  section top.sh
  recorded "git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git $HOME/.oh-my-zsh"
  recorded "zsh-syntax-highlighting"
  recorded "zsh-autosuggestions"
  recorded "$HOME/.tmux/plugins/tpm"
}

@test "top section puts the zsh and tmux configs in place" {
  section top.sh
  recorded "ln -sfn $REPO/configs/zsh/.zshrc $HOME/.zshrc"
  recorded "ln -sfn $REPO/configs/.dircolors $HOME/.dircolors"
  recorded "ln -sfn $REPO/configs/tmux/.tmux.conf $HOME/.tmux.conf"
  recorded "_merge_history_into $REPO/configs/zsh/.zsh_history $HOME/.zsh_history"
}

@test "basic section no longer installs the shell tools or their configs" {
  section basic.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  recorded "apt-get install -y git wget curl zip unzip p7zip-full xclip"
  not_recorded "ohmyzsh"
  not_recorded ".zshrc"
  not_recorded ".tmux.conf"
  not_recorded ".zsh_history"
}

# --- Claude Code ---

@test "claude-code installs from Anthropic's signed apt repo, stable channel" {
  lib_with_claude 0
  install_tool custom claude-code _install_claude_code
  recorded "curl -fsSL -o"
  recorded "$CLAUDE_KEY_URL"
  recorded "$HAKPAK_SYSROOT/etc/apt/keyrings/claude-code.gpg"
  recorded "$(printf '%q' "$CLAUDE_LINE")"
  recorded "$HAKPAK_SYSROOT/etc/apt/sources.list.d/claude-code.list"
  recorded "apt-get install -y claude-code"
}

@test "claude-code checks the repo key against Anthropic's fingerprint before trusting it" {
  lib_with_claude 0
  install_tool custom claude-code _install_claude_code
  recorded "_key_has_fingerprint"
  recorded "$CLAUDE_FPR"
  # The check comes before the keyring is installed.
  check="$(grep -n '_key_has_fingerprint' "$HAKPAK_DRY_RUN_LOG" | head -1 | cut -d: -f1)"
  install="$(grep -n "install -m 644 .*claude-code.gpg" "$HAKPAK_DRY_RUN_LOG" | head -1 | cut -d: -f1)"
  [ "$check" -lt "$install" ]
}

@test "claude-code is never installed by piping a script into a shell, or with npm" {
  section top.sh
  not_recorded "install.sh"
  not_recorded "npm"
  ! grep -n 'claude.ai/install.sh' "$REPO/install/custom.sh"
}

@test "claude-code already installed: no repo or package step, the skills are still linked" {
  lib_with_claude 1
  run install_tool custom claude-code _install_claude_code
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"already installed"* ]]
  not_recorded "apt-get"
  not_recorded "curl"
  recorded "ln -sfn $REPO/.claude/skills/sbx-cli $SKILLS/sbx-cli"
}

@test "a failed Claude Code install is reported and links no skills" {
  unset HAKPAK_DRY_RUN
  stub sudo 'exit 1'
  stub curl 'exit 22'
  lib_with_claude 0
  run install_tool custom claude-code _install_claude_code
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed: claude-code"* ]] || { echo "$output"; return 1; }
  [ ! -e "$SKILLS" ]
}

# --- the repo key fingerprint ---

@test "_key_has_fingerprint passes the key with that fingerprint, spaces and case aside" {
  make_test_key
  lib
  run _key_has_fingerprint "$KEY" "$FPR"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  spaced="$(sed 's/..../& /g' <<< "${FPR,,}")"
  run _key_has_fingerprint "$KEY" "$spaced"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "_key_has_fingerprint fails another key, and a file that is no key" {
  make_test_key
  lib
  run _key_has_fingerprint "$KEY" "$CLAUDE_FPR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"fingerprint"* ]] || { echo "$output"; return 1; }
  echo '<html>not found</html>' > "$BATS_TEST_TMPDIR/page.asc"
  run _key_has_fingerprint "$BATS_TEST_TMPDIR/page.asc" "$CLAUDE_FPR"
  [ "$status" -ne 0 ]
}

@test "_key_has_fingerprint fails a file that holds a second key" {
  make_test_key
  gpg --batch --homedir "$BATS_TEST_TMPDIR/gnupg-src" --quick-gen-key --passphrase '' 'other <o@example.test>' default default never 2>/dev/null ||
    skip "gpg can't make a test key here"
  gpg --batch --homedir "$BATS_TEST_TMPDIR/gnupg-src" --armor --export > "$KEY"
  lib
  run _key_has_fingerprint "$KEY" "$FPR"
  [ "$status" -ne 0 ]
}

@test "add_apt_repo with a fingerprint installs nothing when the downloaded key is another one" {
  unset HAKPAK_DRY_RUN
  make_test_key
  stub curl 'while [ $# -gt 1 ]; do [ "$1" = -o ] && cp "'"$KEY"'" "$2"; shift; done'
  stub sudo 'echo "sudo $*" >> "'"$BATS_TEST_TMPDIR"'/sudo.log"; exit 1'
  lib
  run add_apt_repo claude-code "$CLAUDE_KEY_URL" /etc/apt/keyrings/claude-code.gpg "$CLAUDE_LINE" "$CLAUDE_FPR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"fingerprint"* ]] || { echo "$output"; return 1; }
  [ ! -e "$HAKPAK_SYSROOT/etc/apt/keyrings/claude-code.gpg" ]
  [ ! -e "$HAKPAK_SYSROOT/etc/apt/sources.list.d/claude-code.list" ]
  [ ! -e "$BATS_TEST_TMPDIR/sudo.log" ]
}

@test "add_apt_repo without a fingerprint works as before" {
  lib
  add_apt_repo vendor https://example.test/key.asc /usr/share/keyrings/vendor.gpg \
    'deb [signed-by=/usr/share/keyrings/vendor.gpg] https://example.test/apt stable main'
  not_recorded "_key_has_fingerprint"
  recorded "$HAKPAK_SYSROOT/usr/share/keyrings/vendor.gpg"
}

# --- the skills ---

@test "dry run records one link per skill in .claude/skills and creates nothing" {
  lib
  _link_claude_skills
  for dir in "$REPO"/.claude/skills/*/; do
    name="$(basename "$dir")"
    recorded "ln -sfn $REPO/.claude/skills/$name $SKILLS/$name"
  done
  recorded "mkdir -p $SKILLS"
  [ ! -e "$HOME/.claude" ]
}

@test "every skill in .claude/skills is linked into ~/.claude/skills" {
  unset HAKPAK_DRY_RUN
  lib
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  for dir in "$REPO"/.claude/skills/*/; do
    name="$(basename "$dir")"
    [ "$(readlink "$SKILLS/$name")" = "$REPO/.claude/skills/$name" ] || { ls -la "$SKILLS"; return 1; }
    [ -f "$SKILLS/$name/SKILL.md" ]
  done
}

@test "linking the skills again changes nothing" {
  unset HAKPAK_DRY_RUN
  lib
  _link_claude_skills
  before="$(ls -la --time-style=full-iso "$SKILLS")"
  export HAKPAK_DRY_RUN=1
  run _link_claude_skills
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ] || { cat "$HAKPAK_DRY_RUN_LOG"; return 1; }
  [ "$(ls -la --time-style=full-iso "$SKILLS")" = "$before" ]
}

@test "your own skill of the same name is kept, and the others are still linked" {
  unset HAKPAK_DRY_RUN
  mkdir -p "$SKILLS/sbx-cli"
  echo mine > "$SKILLS/sbx-cli/SKILL.md"
  lib
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"sbx-cli"*"kept"* ]] || { echo "$output"; return 1; }
  [ ! -L "$SKILLS/sbx-cli" ]
  [ "$(cat "$SKILLS/sbx-cli/SKILL.md")" = mine ]
  [ -L "$SKILLS/sbx-arch" ]
}

@test "your own link to a skill of the same name is kept" {
  unset HAKPAK_DRY_RUN
  mkdir -p "$SKILLS" "$BATS_TEST_TMPDIR/mine/sbx-cli"
  ln -s "$BATS_TEST_TMPDIR/mine/sbx-cli" "$SKILLS/sbx-cli"
  lib
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(readlink "$SKILLS/sbx-cli")" = "$BATS_TEST_TMPDIR/mine/sbx-cli" ]
}

@test "a broken link (hakpak cloned somewhere else before) is replaced" {
  unset HAKPAK_DRY_RUN
  mkdir -p "$SKILLS"
  ln -s "$BATS_TEST_TMPDIR/old-clone/.claude/skills/sbx-cli" "$SKILLS/sbx-cli"
  lib
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(readlink "$SKILLS/sbx-cli")" = "$REPO/.claude/skills/sbx-cli" ]
}

@test "skills go under CLAUDE_CONFIG_DIR when it is set" {
  unset HAKPAK_DRY_RUN
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-config"
  lib
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -L "$CLAUDE_CONFIG_DIR/skills/sbx-cli" ]
  [ ! -e "$HOME/.claude" ]
}

@test "a directory in .claude/skills without a SKILL.md is not linked" {
  unset HAKPAK_DRY_RUN
  mkdir -p "$BATS_TEST_TMPDIR/root/.claude/skills/notes" "$BATS_TEST_TMPDIR/root/.claude/skills/real"
  echo x > "$BATS_TEST_TMPDIR/root/.claude/skills/real/SKILL.md"
  lib
  HAKPAK_ROOT="$BATS_TEST_TMPDIR/root"
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -L "$SKILLS/real" ]
  [ ! -e "$SKILLS/notes" ]
}

@test "a failed skill link fails the tool" {
  unset HAKPAK_DRY_RUN
  mkdir -p "$HOME/.claude"
  echo "a file, not a directory" > "$SKILLS"
  lib_with_claude 1
  run install_tool custom claude-code _install_claude_code
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed: claude-code"* ]] || { echo "$output"; return 1; }
}

@test "a broken link of your own, to somewhere that isn't a hakpak clone, is kept" {
  unset HAKPAK_DRY_RUN
  mkdir -p "$SKILLS"
  ln -s "/mnt/unplugged/dotfiles/skills/my-sbx" "$SKILLS/sbx-cli"
  lib
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"sbx-cli"*"kept"* ]] || { echo "$output"; return 1; }
  [ "$(readlink "$SKILLS/sbx-cli")" = "/mnt/unplugged/dotfiles/skills/my-sbx" ]
}

@test "a link to a skill the repo no longer has is removed, other broken links stay" {
  unset HAKPAK_DRY_RUN
  mkdir -p "$SKILLS"
  ln -s "$REPO/.claude/skills/gone-skill" "$SKILLS/gone-skill"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/other" "$SKILLS/other"
  lib
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -L "$SKILLS/gone-skill" ]
  [ -L "$SKILLS/other" ]
}

# --- what top needs from basic ---

@test "git and curl are installed first when they are missing" {
  lib_with_claude 0
  has_command() { case "$1" in git|curl|claude) return 1 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac; }
  install_tool custom oh-my-zsh _install_oh_my_zsh
  recorded "apt-get install -y git"
  : > "$HAKPAK_DRY_RUN_LOG"
  install_tool git tpm https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  recorded "apt-get install -y git"
  : > "$HAKPAK_DRY_RUN_LOG"
  install_tool custom claude-code _install_claude_code
  recorded "apt-get install -y curl"
  [ "$(grep -n 'install -y curl' "$HAKPAK_DRY_RUN_LOG" | cut -d: -f1)" -lt "$(grep -n 'curl -fsSL' "$HAKPAK_DRY_RUN_LOG" | head -1 | cut -d: -f1)" ]
}

@test "git and curl that are already there are not installed again" {
  section top.sh
  not_recorded "apt-get install -y git"
  not_recorded "apt-get install -y curl"
}

# --- a repo that is already configured ---

@test "add_apt_repo with a fingerprint: a keyring that is already there with that key is kept" {
  make_test_key
  mkdir -p "$HAKPAK_SYSROOT/etc/apt/sources.list.d" "$HAKPAK_SYSROOT/etc/apt/keyrings"
  echo "$CLAUDE_LINE" > "$HAKPAK_SYSROOT/etc/apt/sources.list.d/claude-code.list"
  gpg --batch --homedir "$BATS_TEST_TMPDIR/gnupg-src" --export > "$HAKPAK_SYSROOT/etc/apt/keyrings/claude-code.gpg"
  lib
  run add_apt_repo claude-code "$CLAUDE_KEY_URL" /etc/apt/keyrings/claude-code.gpg "$CLAUDE_LINE" "$FPR"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"already configured"* ]]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ] || { cat "$HAKPAK_DRY_RUN_LOG"; return 1; }
}

@test "add_apt_repo with a fingerprint: a keyring that is already there with another key is replaced" {
  make_test_key
  mkdir -p "$HAKPAK_SYSROOT/etc/apt/sources.list.d" "$HAKPAK_SYSROOT/etc/apt/keyrings"
  echo "$CLAUDE_LINE" > "$HAKPAK_SYSROOT/etc/apt/sources.list.d/claude-code.list"
  gpg --batch --homedir "$BATS_TEST_TMPDIR/gnupg-src" --export > "$HAKPAK_SYSROOT/etc/apt/keyrings/claude-code.gpg"
  lib
  run add_apt_repo claude-code "$CLAUDE_KEY_URL" /etc/apt/keyrings/claude-code.gpg "$CLAUDE_LINE" "$CLAUDE_FPR"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"not the expected key"* ]] || { echo "$output"; return 1; }
  recorded "$CLAUDE_KEY_URL"
  recorded "_key_has_fingerprint"
  recorded "install -m 644"
}
