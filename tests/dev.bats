#!/usr/bin/env bats
# Tests for the Dev section: developer tools (ripgrep, fd, jq, delta, gh,
# shellcheck, shfmt), toolchains (uv with Python, fnm with Node, Go, Rust),
# Claude Code with plugin marketplaces and plugins, and the shell and git
# configs. Section runs go through the dry run; config and sandbox steps use
# the real adapter inside a temp home and a temp system root.

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

# Load the install module as if none of the named commands were installed,
# so a test doesn't depend on what the test host has.
lib_without() {
  lib
  _MISSING=" $* "
  has_command() {
    case "$_MISSING" in *" $1 "*) return 1 ;; esac
    command -v "$1" >/dev/null 2>&1
  }
}

# Stub commands on PATH for real-adapter tests: stub <name> <script body>
stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Make the temp system root look like a Docker Sandbox.
in_sandbox() {
  export SANDBOX_NAME=box
  mkdir -p "$HAKPAK_SYSROOT/etc"
  printf '# sandbox env\nexport FOO=1\n' > "$HAKPAK_SYSROOT/etc/sandbox-persistent.sh"
}

DEV_TOOLS="build-essential ripgrep jq git-delta gh shellcheck shfmt fd uv python ast-grep ruff ty zizmor prek fnm node go actionlint rust claude-code claude-marketplaces modern-python rust-review gh-cli git-cleanup property-based-testing static-analysis differential-review security-audit claude-code-config"

# --- the section in the manifest ---

@test "dev section lists its tools, toolchains, plugins and the config repo" {
  lib
  [ "$(toolset_rows dev | cut -f3 | paste -sd' ')" = "$DEV_TOOLS" ] ||
    { toolset_rows dev | cut -f3 | paste -sd' '; return 1; }
  toolset_check
}

@test "dev comes right after top" {
  lib
  ids="$(for s in "${HAKPAK_SECTIONS[@]}"; do echo "${s%%:*}"; done | paste -sd' ')"
  [[ "$ids " == "top dev system "* ]] || { echo "$ids"; return 1; }
  run bash "$REPO/install/setup.sh" --help
  [[ "$output" == *"dev "*"Dev"* ]] || { echo "$output"; return 1; }
}

@test "build-essential moved from system to dev" {
  lib
  ! toolset_rows system | cut -f3 | grep -qx build-essential
  toolset_rows dev | cut -f3 | grep -qx build-essential
}

@test "go and claude-code are the same rows as in environment and top" {
  lib
  [ "$(toolset_rows dev | awk -F'\t' '$3 == "go"' | cut -f2-4)" = \
    "$(toolset_rows environment | awk -F'\t' '$3 == "go"' | cut -f2-4)" ]
  [ "$(toolset_rows dev | awk -F'\t' '$3 == "claude-code"' | cut -f2-4)" = \
    "$(toolset_rows top | awk -F'\t' '$3 == "claude-code"' | cut -f2-4)" ]
}

@test "nothing in dev builds or runs containers, or sets up Claude Code's own sandbox" {
  lib
  for t in docker podman devcontainer bubblewrap socat ipset iptables; do
    ! toolset_rows dev | grep -qw "$t" || { echo "dev lists $t"; return 1; }
  done
}

@test "the README names the dev section and lists its tools" {
  grep -q '^Sections: `top`, `dev`, `system`,' "$REPO/README.md"
  grep -qx '## Dev' "$REPO/README.md"
  grep -q '^\* ruff (uv)' "$REPO/README.md"
  grep -q '^\* modern-python (plugin)' "$REPO/README.md"
  run bash "$REPO/tools/gen-readme" --check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# --- the uv and plugin kinds ---

@test "check reports a plugin row without a marketplace" {
  export HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/toolset.txt"
  printf 'dev plugin modern-python\n' > "$HAKPAK_TOOLSET"
  lib
  run toolset_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugin needs a marketplace"* ]] || { echo "$output"; return 1; }
}

@test "uv kind installs a tool with uv tool install, under its package name" {
  lib_without ast-grep ruff
  install_tool uv ruff
  install_tool uv ast-grep ast-grep-cli
  recorded "uv tool install ruff"
  recorded "uv tool install ast-grep-cli"
}

@test "uv kind skips a tool that is already there" {
  stub ruff 'exit 0'
  lib
  run install_tool uv ruff
  [[ "$output" == *"ruff already installed"* ]] || { echo "$output"; return 1; }
  not_recorded "uv tool install"
}

@test "plugin kind installs name@marketplace with the claude CLI" {
  lib
  install_tool plugin modern-python trailofbits
  recorded "claude plugin install modern-python@trailofbits"
}

@test "plugin kind fails without claude, outside a dry run" {
  export HAKPAK_DRY_RUN=0
  lib_without claude
  run install_tool plugin modern-python trailofbits
  [ "$status" -ne 0 ]
  [[ "$output" == *"Claude Code"* ]] || { echo "$output"; return 1; }
}

@test "plugin and marketplace names must be plain names" {
  lib
  run install_tool plugin 'x;rm' trailofbits
  [ "$status" -ne 0 ]
  run install_tool plugin modern-python '--scope'
  [ "$status" -ne 0 ]
  not_recorded "claude plugin install"
}

# --- the section script ---

@test "dev section runs cleanly in dry run" {
  section dev.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$(find "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT" -mindepth 1 -print -quit)" ]
}

@test "dev section refreshes the package lists and installs its apt tools in one call" {
  section dev.sh
  recorded "apt-get update"
  recorded "apt-get install -y build-essential ripgrep jq git-delta gh shellcheck shfmt"
}

@test "fd comes from apt's fd-find and is linked as fd" {
  lib_without fd fdfind
  install_tool custom fd _install_fd
  recorded "apt-get install -y fd-find"
  recorded "ln -sfn /usr/bin/fdfind $HOME/.local/bin/fd"
}

@test "uv is a release binary checked against its checksum, not a piped installer" {
  lib_without uv
  install_tool custom uv _install_uv_release
  recorded "https://github.com/astral-sh/uv/releases/latest/download/uv-"
  recorded ".tar.gz.sha256"
  recorded "verify_sha256"
  recorded "install -m 755"
  recorded "/usr/local/bin/uv"
  recorded "/usr/local/bin/uvx"
  not_recorded "astral.sh/uv/install.sh"
}

@test "an installed uv is kept" {
  stub uv 'exit 0'
  lib
  run install_tool custom uv _install_uv_release
  [[ "$output" == *"uv already installed"* ]] || { echo "$output"; return 1; }
  not_recorded "curl"
}

@test "Python 3.13 is installed with uv" {
  lib
  install_tool custom python _install_uv_python
  recorded "uv python install 3.13"
}

@test "fnm is a pinned release, checked against a hash kept in hakpak" {
  lib_without fnm unzip
  install_tool custom fnm _install_fnm
  recorded "https://github.com/Schniz/fnm/releases/download/v"
  recorded "_sha256_is"
  recorded "/usr/local/bin/fnm"
  not_recorded "fnm.vercel.app"
  # the hash is a full sha256, for both CPUs
  [ "$(grep -cE "^[[:space:]]+(amd64|arm64)\) .*sha=[0-9a-f]{64}" "$REPO/install/custom.sh")" -eq 2 ]
}

@test "_sha256_is accepts the right hash and refuses another" {
  lib
  printf 'hello\n' > "$BATS_TEST_TMPDIR/f"
  _sha256_is "$BATS_TEST_TMPDIR/f" 5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03
  run _sha256_is "$BATS_TEST_TMPDIR/f" 0000000000000000000000000000000000000000000000000000000000000000
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
}

@test "Node 22 is installed with fnm, and pnpm through corepack" {
  lib
  install_tool custom node _install_node
  recorded "fnm install 22"
  recorded "fnm default 22"
  recorded "corepack enable pnpm"
  recorded "corepack prepare pnpm@latest --activate"
  not_recorded "npm install -g"
}

@test "a Node 22 with pnpm that is already there is kept, with no download" {
  bin="$HOME/.local/share/fnm/aliases/default/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho v22.1.0\n' > "$bin/node"
  printf '#!/bin/sh\n' > "$bin/pnpm"
  chmod +x "$bin/node" "$bin/pnpm"
  lib
  run install_tool custom node _install_node
  [[ "$output" == *"already installed"* ]] || { echo "$output"; return 1; }
  not_recorded "fnm install"
  not_recorded "corepack"
  # another major version is not "already there"
  printf '#!/bin/sh\necho v20.9.0\n' > "$bin/node"
  install_tool custom node _install_node
  recorded "fnm install 22"
}

@test "Rust comes from rustup-init, checked against its sha256, and leaves your shell files alone" {
  lib_without rustup
  install_tool custom rust _install_rust
  recorded "https://static.rust-lang.org/rustup/dist/"
  recorded "rustup-init.sha256"
  recorded "verify_sha256"
  recorded "rustup-init -y --no-modify-path --profile default --default-toolchain stable"
  not_recorded "sh.rustup.rs"
}

@test "an installed rustup is kept" {
  mkdir -p "$HOME/.cargo/bin"
  printf '#!/bin/sh\n' > "$HOME/.cargo/bin/rustup"
  chmod +x "$HOME/.cargo/bin/rustup"
  lib_without rustup
  run install_tool custom rust _install_rust
  [[ "$output" == *"rust already installed"* ]] || { echo "$output"; return 1; }
  not_recorded "rustup-init"
}

@test "dev section installs actionlint with go and clones the Trail of Bits config repo" {
  section dev.sh
  recorded "go install -v github.com/rhysd/actionlint/cmd/actionlint@latest"
  recorded "git clone --depth 1 https://github.com/trailofbits/claude-code-config $HAKPAK_OPT/claude-code-config"
}

@test "no installer script is piped into a shell" {
  section dev.sh
  ! grep -E '\| *(ba)?sh' "$HAKPAK_DRY_RUN_LOG"
  ! grep -nE 'curl[^|]*\| *(sudo )?(ba)?sh' "$REPO/install/dev.sh"
}

# --- Claude Code: marketplaces, plugins, settings ---

@test "dev section registers the three marketplaces and hakpak's own" {
  section dev.sh
  recorded "claude plugin marketplace add trailofbits/skills"
  recorded "claude plugin marketplace add trailofbits/skills-curated"
  recorded "claude plugin marketplace add anthropics/skills"
  recorded "claude plugin marketplace add $REPO"
}

@test "dev section installs the seven plugins and the Cloudflare security audit skill" {
  section dev.sh
  for p in modern-python rust-review gh-cli git-cleanup property-based-testing static-analysis differential-review; do
    recorded "claude plugin install $p@trailofbits"
  done
  recorded "claude plugin install security-audit@hakpak"
}

@test "hakpak's marketplace file lists the Cloudflare skill as a plugin" {
  f="$REPO/.claude-plugin/marketplace.json"
  [ "$(jq -r .name "$f")" = hakpak ]
  [ "$(jq -r '.plugins | length' "$f")" -eq 1 ]
  [ "$(jq -r '.plugins[0].name' "$f")" = security-audit ]
  [ "$(jq -r '.plugins[0].source.source' "$f")" = github ]
  [ "$(jq -r '.plugins[0].source.repo' "$f")" = cloudflare/security-audit-skill ]
  [ "$(jq -r '.plugins[0].strict' "$f")" = false ]
}

@test "the marketplace names in the manifest match the registered marketplaces" {
  lib
  while IFS=$'\t' read -r _ kind _ market _; do
    [ "$kind" = plugin ] || continue
    case "$market" in trailofbits|hakpak) ;; *) echo "unexpected marketplace: $market"; return 1 ;; esac
  done < <(toolset_rows dev)
}

@test "Claude Code settings are never written, and bypassPermissions is never set" {
  section dev.sh
  not_recorded "settings.json"
  not_recorded "bypassPermissions"
  ! grep -rn 'bypassPermissions' "$REPO/install" "$REPO/configs" "$REPO/system/.dev"
}

@test "marketplaces fail without claude, outside a dry run" {
  export HAKPAK_DRY_RUN=0
  lib_without claude
  run install_tool custom claude-marketplaces _install_claude_marketplaces
  [ "$status" -ne 0 ]
  [[ "$output" == *"Claude Code"* ]] || { echo "$output"; return 1; }
}

@test "the closing hint points at the Trail of Bits config repo" {
  section dev.sh
  [[ "$output" == *"$HAKPAK_OPT/claude-code-config"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"/trailofbits:config"* ]]
  [[ "$output" != *"sandbox"* ]] || { echo "$output"; return 1; }
}

@test "without the clone, the hint doesn't send you to a directory that isn't there" {
  export HAKPAK_DRY_RUN=0
  lib
  run dev_hint
  [[ "$output" != *"claude-code-config"* ]] || { echo "$output"; return 1; }
  mkdir -p "$HAKPAK_OPT/claude-code-config/.git"
  run dev_hint
  [[ "$output" == *"$HAKPAK_OPT/claude-code-config"* ]]
}

# --- configs ---

@test "system/.dev is valid in bash and zsh, and quiet when no tool is there" {
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '. "$1" && echo ok' _ "$REPO/system/.dev"
  [ "$output" = ok ] || { echo "$output"; return 1; }
  command -v zsh >/dev/null || skip "needs zsh"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -fc '. "$1" && echo ok' _ "$REPO/system/.dev"
  [ "$output" = ok ] || { echo "$output"; return 1; }
}

@test "system/.dev puts the cargo, fnm, Go and uv tool directories on PATH, once" {
  mkdir -p "$HOME/.cargo/bin" "$HOME/.local/share/fnm/aliases/default/bin" "$HOME/.local/bin"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '. "$1"; . "$1"; echo "$PATH"' _ "$REPO/system/.dev"
  for d in "$HOME/.cargo/bin" "$HOME/.local/share/fnm/aliases/default/bin" "$HOME/.local/bin" /usr/local/go/bin; do
    [ "$(tr ':' '\n' <<< "$output" | grep -cxF "$d")" -eq 1 ] || { echo "$d in $output"; return 1; }
  done
}

@test "system/.dev: an interactive zsh loads fnm, so cd picks the Node version" {
  command -v zsh >/dev/null || skip "needs zsh"
  stub fnm 'echo "export FNM_LOADED=1"'
  run env -i HOME="$HOME" PATH="$PATH" TERM=xterm zsh -fic '. "$1"; echo "loaded=$FNM_LOADED"' _ "$REPO/system/.dev"
  [[ "$output" == *"loaded=1"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"system/.dev:"* ]] || { echo "$output"; return 1; }
  # a script's zsh, and bash, don't
  run env -i HOME="$HOME" PATH="$PATH" zsh -fc '. "$1"; echo "loaded=$FNM_LOADED"' _ "$REPO/system/.dev"
  [ "$output" = "loaded=" ] || { echo "$output"; return 1; }
  run env -i HOME="$HOME" PATH="$PATH" bash -ic '. "$1"; echo "loaded=$FNM_LOADED"' _ "$REPO/system/.dev"
  [[ "$output" == *"loaded="* ]] && [[ "$output" != *"loaded=1"* ]]
}

@test "system/.dev puts the Rust and Node installed here ahead of the system's" {
  mkdir -p "$HOME/.cargo/bin" "$HOME/.local/share/fnm/aliases/default/bin" "$HOME/.local/bin"
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '. "$1"; echo "$PATH"' _ "$REPO/system/.dev"
  [[ "$output" == "$HOME/.local/share/fnm/aliases/default/bin:$HOME/.cargo/bin:"*":/usr/bin:"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *":/usr/bin:"*":$HOME/.local/bin" ]] || { echo "$output"; return 1; }
}

@test "system/.dev leaves out directories that are not there" {
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '. "$1"; echo "$PATH"' _ "$REPO/system/.dev"
  [[ "$output" != *".cargo/bin"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"fnm"* ]]
}

@test "system/.dev hardens npm and offers claude-yolo as an alias only" {
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -ic '. "$1"; echo "$NPM_CONFIG_IGNORE_SCRIPTS $NPM_CONFIG_MIN_RELEASE_AGE $PNPM_CONFIG_MINIMUM_RELEASE_AGE"; alias claude-yolo' _ "$REPO/system/.dev"
  # a day: npm counts days, pnpm minutes
  [[ "$output" == *"true 1 1440"* ]] || { echo "$output"; return 1; }
  # not the name npm ignores
  ! grep -q 'NPM_CONFIG_MINIMUM_RELEASE_AGE' "$REPO/system/.dev"
  [[ "$output" == *"claude --dangerously-skip-permissions"* ]]
}

@test "the git config makes delta the pager" {
  f="$REPO/configs/git/dev.gitconfig"
  [ "$(git config -f "$f" core.pager)" = delta ]
  [ "$(git config -f "$f" merge.conflictstyle)" = diff3 ]
  [ "$(git config -f "$f" interactive.diffFilter)" = "delta --color-only" ]
}

@test "the global gitignore doesn't hide .claude" {
  ! grep -q '^\.claude' "$REPO/configs/git/gitignore"
  grep -qx 'node_modules/' "$REPO/configs/git/gitignore"
}

@test "dev git config: one include is added and your own settings stay" {
  export HAKPAK_DRY_RUN=0
  stub delta 'exit 0'
  git config --global user.name 'Someone Else'
  git config --global core.pager less
  lib
  link_dev_git_config
  link_dev_git_config
  [ "$(git config --global user.name)" = 'Someone Else' ]
  [ "$(git config --global --get-all include.path | grep -cxF "$REPO/configs/git/dev.gitconfig")" -eq 1 ]
  [ "$(git config --global core.excludesFile)" = "$REPO/configs/git/gitignore" ]
  grep -q 'pager = less' "$HOME/.gitconfig"
}

@test "dev git config: an excludes file you already set is kept" {
  export HAKPAK_DRY_RUN=0
  stub delta 'exit 0'
  git config --global core.excludesFile "$HOME/mine"
  lib
  link_dev_git_config
  [ "$(git config --global core.excludesFile)" = "$HOME/mine" ]
}

@test "dev git config: without delta nothing is included" {
  export HAKPAK_DRY_RUN=0
  lib_without delta
  run link_dev_git_config
  [ "$status" -eq 0 ]
  [ -z "$(git config --global --get-all include.path)" ]
}

# --- sbx (Docker Sandboxes) ---

@test "is_sbx needs both the sandbox name and its environment file" {
  lib
  ! is_sbx
  SANDBOX_NAME=box
  ! is_sbx
  in_sandbox
  is_sbx
  unset SANDBOX_NAME
  ! is_sbx
}

@test "outside a sandbox the dev section doesn't touch the sandbox environment file" {
  section dev.sh
  not_recorded "sandbox-persistent.sh"
}

@test "in a sandbox the dev section adds its environment to the persistent file" {
  in_sandbox
  section dev.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  recorded "sandbox-persistent.sh"
}

@test "sandbox environment: one marked line sources system/.dev, and re-runs add nothing" {
  export HAKPAK_DRY_RUN=0
  in_sandbox
  f="$HAKPAK_SYSROOT/etc/sandbox-persistent.sh"
  lib
  persist_dev_env_in_sbx
  persist_dev_env_in_sbx
  [ "$(grep -c 'hakpak: dev tools' "$f")" -eq 1 ] || { cat "$f"; return 1; }
  grep -q "$REPO/system/.dev" "$f"
  grep -qx 'export FOO=1' "$f"
  # the file still loads, and brings the dev environment with it
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '. "$1"; echo "$FOO $NPM_CONFIG_IGNORE_SCRIPTS"' _ "$f"
  [ "$output" = "1 true" ] || { echo "$output"; return 1; }
}

@test "sandbox environment: the line still succeeds when the clone is gone" {
  export HAKPAK_DRY_RUN=0
  in_sandbox
  f="$HAKPAK_SYSROOT/etc/sandbox-persistent.sh"
  lib
  persist_dev_env_in_sbx
  sed "s|$REPO/system/.dev|/gone/system/.dev|g" "$f" > "$f.moved"
  run bash -ec '. "$1" && echo loaded' _ "$f.moved"
  [ "$output" = loaded ] || { echo "$output"; return 1; }
}

@test "sandbox environment: the file is written in place, not replaced" {
  export HAKPAK_DRY_RUN=0
  in_sandbox
  f="$HAKPAK_SYSROOT/etc/sandbox-persistent.sh"
  before="$(stat -c %i "$f")"
  lib
  persist_dev_env_in_sbx
  [ "$(stat -c %i "$f")" = "$before" ]
}

@test "sandbox environment: a line left by a clone that moved is replaced" {
  export HAKPAK_DRY_RUN=0
  in_sandbox
  f="$HAKPAK_SYSROOT/etc/sandbox-persistent.sh"
  echo 'if [ -r /old/system/.dev ]; then . /old/system/.dev; fi  # hakpak: dev tools' >> "$f"
  lib
  persist_dev_env_in_sbx
  [ "$(grep -c 'hakpak: dev tools' "$f")" -eq 1 ] || { cat "$f"; return 1; }
  ! grep -q '/old/system' "$f"
}

@test "in a sandbox a read-only skills directory is skipped, not a failure" {
  export HAKPAK_DRY_RUN=0
  mkdir -p "$HOME/.claude/skills"
  lib
  _dir_is_writable() { return 1; }
  run _link_claude_skills
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"read-only"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"sbx skills"* ]]
  [ -z "$(ls -A "$HOME/.claude/skills")" ]
}

@test "in a sandbox the closing hint warns against the Trail of Bits settings.json" {
  in_sandbox
  section dev.sh
  [[ "$output" == *"sandbox"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"settings.json"* ]]
}

@test "in a sandbox a failed install names the network policy and how to allow a host" {
  in_sandbox
  lib
  HAKPAK_FAILED=(uv)
  run install_summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"sbx policy log box"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"sbx policy allow network --sandbox box"* ]]
}

@test "outside a sandbox a failed install says nothing about sbx" {
  lib
  HAKPAK_FAILED=(uv)
  run install_summary
  [ "$status" -ne 0 ]
  [[ "$output" != *"sbx"* ]] || { echo "$output"; return 1; }
}

@test "a sandbox name that isn't a plain name is not printed into a command" {
  in_sandbox
  export SANDBOX_NAME='box; rm -rf /'
  lib
  HAKPAK_FAILED=(uv)
  run install_summary
  [[ "$output" != *"rm -rf"* ]] || { echo "$output"; return 1; }
}

# --- section rules shared by every section ---

@test "dev section checks it isn't run as root and calls no package tool directly" {
  grep -q '^require_normal_user' "$REPO/install/dev.sh"
  run grep -nE '^\s*(sudo )?(apt|apt-get|go|pip3?|git|uv|cargo|claude) ' "$REPO/install/dev.sh"
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
}
