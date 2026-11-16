#!/usr/bin/env bats
# Tests for the AI section: Claude Code with the skills from .claude/skills,
# the plugin marketplaces and skill plugins, and the Trail of Bits Claude
# Code config. Section runs go through the dry run; sandbox steps use the
# real adapter inside a temp home and a temp system root.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_SYSROOT="$BATS_TEST_TMPDIR/sysroot"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  export NO_COLOR=1
  unset CLAUDE_CONFIG_DIR SANDBOX_NAME GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
  export GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT"
  : > "$HAKPAK_DRY_RUN_LOG"
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

# Make the temp system root look like a Docker Sandbox.
in_sandbox() {
  export SANDBOX_NAME=box
  mkdir -p "$HAKPAK_SYSROOT/etc"
  printf '# sandbox env\nexport FOO=1\n' > "$HAKPAK_SYSROOT/etc/sandbox-persistent.sh"
}

AI_TOOLS="claude-code claude-marketplaces modern-python rust-review gh-cli git-cleanup property-based-testing static-analysis differential-review security-audit claude-code-config"

# --- the section in the manifest ---

@test "ai section lists Claude Code, the marketplaces, the skill plugins and the config" {
  lib
  [ "$(toolset_rows ai | cut -f3 | paste -sd' ')" = "$AI_TOOLS" ] ||
    { toolset_rows ai | cut -f3 | paste -sd' '; return 1; }
  toolset_check
}

@test "ai comes right after dev, and setup knows it" {
  lib
  ids="$(for s in "${HAKPAK_SECTIONS[@]}"; do echo "${s%%:*}"; done | paste -sd' ')"
  [[ "$ids " == "top dev ai network "* ]] || { echo "$ids"; return 1; }
  run bash "$REPO/install/setup.sh" --help
  [[ "$output" == *"ai "*"AI"* ]] || { echo "$output"; return 1; }
}

@test "every ai row is also in dev, the same, so dev stays as it was" {
  lib
  dev="$(toolset_rows dev | cut -f2-5)"
  while IFS= read -r row; do
    grep -qxF -- "$row" <<< "$dev" || { echo "not in dev: $row"; return 1; }
  done < <(toolset_rows ai | cut -f2-5)
  toolset_rows dev | cut -f3 | grep -qx claude-code
  toolset_rows dev | cut -f3 | grep -qx ruff
}

@test "every Claude Code row of dev (claude-* and plugins) is in ai too" {
  lib
  ai="$(toolset_rows ai | cut -f2-5)"
  while IFS= read -r row; do
    grep -qxF -- "$row" <<< "$ai" || { echo "not in ai: $row"; return 1; }
  done < <(toolset_rows dev | awk -F'\t' '$3 ~ /^claude-/ || $2 == "plugin"' | cut -f2-5)
}

@test "ai has none of dev's toolchains" {
  lib
  for t in build-essential ripgrep uv python fnm node go rust ruff; do
    ! toolset_rows ai | cut -f3 | grep -qx "$t" || { echo "ai lists $t"; return 1; }
  done
}

@test "the README names the ai section and lists its tools" {
  grep -q '^Sections: `top`, `dev`, `ai`, `network`,' "$REPO/README.md"
  grep -qx '## AI' "$REPO/README.md"
  run bash "$REPO/tools/gen-readme" --check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# --- the section run ---

@test "ai section runs cleanly in dry run" {
  section ai.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "ai section installs Claude Code from Anthropic's apt repo and links the skills" {
  section ai.sh
  recorded "claude-code"
  for s in "$REPO"/.claude/skills/*/; do
    s="${s%/}"
    recorded "ln -sfn $s $HOME/.claude/skills/${s##*/}"
  done
}

@test "ai section registers the marketplaces and installs the skill plugins" {
  section ai.sh
  recorded "claude plugin marketplace add trailofbits/skills"
  recorded "claude plugin marketplace add trailofbits/skills-curated"
  recorded "claude plugin marketplace add anthropics/skills"
  recorded "claude plugin marketplace add $REPO"
  for p in modern-python rust-review gh-cli git-cleanup property-based-testing static-analysis differential-review; do
    recorded "claude plugin install $p@trailofbits"
  done
  recorded "claude plugin install security-audit@hakpak"
}

@test "ai section clones the Trail of Bits config and says how to apply it" {
  section ai.sh
  recorded "$HAKPAK_OPT/claude-code-config"
  [[ "$output" == *"/trailofbits:config"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"sandbox"* ]] || { echo "$output"; return 1; }
}

@test "ai section doesn't install toolchains or touch git and shell configs" {
  section ai.sh
  not_recorded "include.path"
  not_recorded "rustup"
  not_recorded "uv tool install"
  [[ "$output" != *"~/.cargo/bin"* ]] || { echo "$output"; return 1; }
}

@test "ai section never writes Claude Code settings" {
  section ai.sh
  not_recorded "settings.json"
  not_recorded "bypassPermissions"
}

@test "ai section checks it isn't run as root and calls no package tool directly" {
  grep -q '^require_normal_user' "$REPO/install/ai.sh"
  ! grep -nE '^[^#]*\b(apt|apt-get|pipx|git|claude) ' "$REPO/install/ai.sh" | grep -v "step 'package lists'"
}

# --- in a Docker Sandbox ---

@test "in a sandbox the ai section warns against the Trail of Bits settings.json" {
  in_sandbox
  section ai.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"sandbox"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"settings.json"* ]]
}

@test "in a sandbox the ai section leaves the sandbox environment file alone" {
  in_sandbox
  before="$(cat "$HAKPAK_SYSROOT/etc/sandbox-persistent.sh")"
  section ai.sh
  not_recorded "sandbox-persistent.sh"
  [ "$(cat "$HAKPAK_SYSROOT/etc/sandbox-persistent.sh")" = "$before" ]
}
