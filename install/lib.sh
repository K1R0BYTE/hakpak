#!/usr/bin/env bash
# hakpak install module. Source it from a section script:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#   install_section web        # every `web` row of install/toolset.txt
#   install_summary
#
# install_section calls `install_tool <kind> <name> [source...]` per row;
# you can also call install_tool directly.
#
# Tool kinds (see CONTEXT.md):
#   apt    <name> [packages]          apt-get install (packages default to name)
#   go     <name> <module@version>    go install into $GOPATH (skips if the binary exists)
#   pipx   <name> [spec]              pipx install (skips if the command exists)
#   gem    <name> [gem]               gem install (skips if the command exists)
#   git    <name> <url> [dest]        shallow clone to dest, default $HAKPAK_OPT/<name>
#   venv   <name> <url>               git clone + .venv + pip install -r requirements.txt
#   url    <name> <url> <dest>        download one file (skips if dest exists)
#   uv     <name> [package]           uv tool install (skips if the command exists)
#   plugin <name> <marketplace>       claude plugin install <name>@<marketplace>
#   custom <name> <function>          call a function (install/custom.sh) that uses `run_step`
#
# One failing tool doesn't stop the section; install_summary lists the
# failures and returns non-zero.
#
# Configs (files in configs/) go into place with:
#   link_config   <configs/path> <target>   symlink in $HOME, copy under /etc
#   merge_history <configs/path> <target>   add curated zsh history to yours
# Both are safe to re-run.
#
# Vendor downloads (used by custom steps in install/custom.sh):
#   add_apt_repo <name> <key-url> <keyring> <source line> [fingerprint]   signed vendor apt repo
#   verify_sha256 <file> <sums> [asset]                      check a download's hash
#   verify_gpg_signature <key.asc> <sig> <file>              check a detached signature
# Call the verify_* checks through run_step, so a dry run records them.
#
# Adapters: every side-effecting command goes through `run_step`. Normally it
# executes; with HAKPAK_DRY_RUN=1 it records the command (one shell-quoted
# line per command) to $HAKPAK_DRY_RUN_LOG, or stdout, and changes nothing.

HAKPAK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HAKPAK_OPT="${HAKPAK_OPT:-/opt}"
# Prefix for system paths: /etc targets of link_config, and the /proc file
# is_wsl reads. Empty on a real install; tests point it at a temp dir.
HAKPAK_SYSROOT="${HAKPAK_SYSROOT:-}"
export HAKPAK_ROOT HAKPAK_OPT HAKPAK_SYSROOT

export GOPATH="$HAKPAK_OPT/go"
export GO111MODULE=on
case ":$PATH:" in
  *":/usr/local/go/bin:"*) ;;
  *) PATH="/usr/local/go/bin:$PATH" ;;
esac
case ":$PATH:" in
  *":$GOPATH/bin:"*) ;;
  *) PATH="$PATH:$GOPATH/bin" ;;
esac
# pipx puts tools here
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$PATH:$HOME/.local/bin" ;;
esac
export PATH

HAKPAK_FAILED=()

_RED="\033[1;31m"
_GREEN="\033[1;32m"
_NOCOLOR="\033[0m"
# NO_COLOR (set and not empty, see no-color.org) turns hakpak's colors off.
if [ -n "${NO_COLOR:-}" ]; then
  _RED="" _GREEN="" _NOCOLOR=""
fi

log() {
  echo -e "[*] ${_RED}${1}${_NOCOLOR}"
}

log_ok() {
  echo -e "[+] ${_GREEN}${1}${_NOCOLOR}"
}

# The seam: real adapter runs the command, dry-run adapter records it.
run_step() {
  if [ "${HAKPAK_DRY_RUN:-0}" = "1" ]; then
    local line
    line="$(printf '%q ' "$@")"
    line="${line% }"
    if [ -n "${HAKPAK_DRY_RUN_LOG:-}" ]; then
      echo "$line" >> "$HAKPAK_DRY_RUN_LOG"
    else
      echo "would run: $line"
    fi
    return 0
  fi
  "$@"
}

# Run a step that isn't a tool install (config, service) and count a
# failure in the summary: step <label> <command...>
# link_config, merge_history, start_zsh_from_bash and the dev config steps are called directly: they send their own
# commands through run_step, so a dry run records what they would do.
step() {
  local label="$1" rc
  shift
  case "$1" in
    link_config|merge_history|start_zsh_from_bash|link_dev_git_config|persist_dev_env_in_sbx) "$@" ;;
    *) run_step "$@" ;;
  esac
  rc=$?
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  echo "failed: $label"
  HAKPAK_FAILED+=("$label")
  return 1
}

# A private temp dir (mode 700). In dry run, a placeholder path is returned
# and nothing is created.
make_temp_dir() {
  if [ "${HAKPAK_DRY_RUN:-0}" = "1" ]; then
    echo "${TMPDIR:-/tmp}/hakpak-dry-run"
    return 0
  fi
  mktemp -d "${TMPDIR:-/tmp}/hakpak.XXXXXXXX"
}

# Section scripts run as your normal user and call sudo only for the steps
# that need root (apt, /usr/local, /etc). Run as root, user tools (pipx,
# go, oh-my-zsh, history) would land in root's home instead of yours.
# HAKPAK_ALLOW_ROOT=1 skips the check, e.g. in a container that only has root.
require_normal_user() {
  [ "${HAKPAK_DRY_RUN:-0}" = "1" ] && return 0
  [ "${HAKPAK_ALLOW_ROOT:-0}" = "1" ] && return 0
  if [ "${_HAKPAK_EUID:-$EUID}" -eq 0 ]; then
    echo "Run hakpak as your normal user, not as root or with sudo. It asks for your password when a step needs it."
    exit 1
  fi
  if ! has_command sudo; then
    echo "hakpak needs sudo. Install it and add your user to the sudo group first."
    exit 1
  fi
}

# Make a directory for a tool. Where you can't write (a fresh /opt), it's
# made with sudo and handed to your user, so the tool itself runs without sudo.
ensure_dir() {
  local dir="$1"
  if ! _needs_sudo "$dir/."; then
    run_step mkdir -p "$dir"
  else
    run_step sudo mkdir -p "$dir" &&
      run_step sudo chown "$(id -un):$(id -gn)" "$dir"
  fi
}

# True when you can't write to the directory that would hold <path> (its
# nearest existing parent).
_needs_sudo() {
  local parent
  parent="$(dirname "$1")"
  while [ ! -e "$parent" ]; do
    parent="$(dirname "$parent")"
  done
  [ ! -w "$parent" ]
}

# Run a step that changes <target>, with sudo only when needed:
# _run_at <target> <command...>
_run_at() {
  local target="$1"
  shift
  if _needs_sudo "$target"; then
    run_step sudo "$@"
  else
    run_step "$@"
  fi
}

# Resolve a path under configs/ to its full path. Fails for a missing file
# or a path that leaves configs/.
_config_source() {
  local rel="$1"
  case "/$rel/" in
    *"/../"*|//*) echo "config path must stay in configs/: $rel"; return 1 ;;
  esac
  [ -f "$HAKPAK_ROOT/configs/$rel" ] || { echo "no config $rel in configs/"; return 1; }
  echo "$HAKPAK_ROOT/configs/$rel"
}

# The first backup of a real file is <target>.bak; it's never overwritten.
# If it already exists (from before hakpak), the file goes to .bak.<time>.
_backup_path() {
  local target="$1"
  if [ -e "$target.bak" ] || [ -L "$target.bak" ]; then
    echo "$target.bak.$(date +%Y%m%d%H%M%S)"
  else
    echo "$target.bak"
  fi
}

# Put a config from configs/ in place: link_config <configs/path> <target>
#   - in your home: a symlink into the repo, so edits show up in git
#   - under /etc: a copy (install -m 644), because root services read it
#     and shouldn't follow a link into a user-owned repo
# A real file at the target is backed up once; a stale link is replaced; a
# target that's already right is left alone. sudo is used only when the
# target's directory isn't writable.
link_config() {
  local src target="$2"
  src="$(_config_source "$1")" || { echo "$src"; return 1; }
  case "$target" in
    /etc/*) target="$HAKPAK_SYSROOT$target"; _copy_config "$src" "$target"; return ;;
  esac
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
    log_ok "$target already linked"
    return 0
  fi
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    _run_at "$target" mv "$target" "$(_backup_path "$target")" || return 1
  fi
  _run_at "$target" ln -sfn "$src" "$target"
}

# True if target is a real file (not a link) with the same content as src.
config_up_to_date() {
  [ -f "$2" ] && [ ! -L "$2" ] && cmp -s "$1" "$2"
}

_copy_config() {
  local src="$1" target="$2"
  if config_up_to_date "$src" "$target"; then
    log_ok "$target already up to date"
    return 0
  fi
  if [ -L "$target" ]; then
    # An older hakpak linked it; a link holds nothing to back up.
    _run_at "$target" rm -f "$target" || return 1
  elif [ -e "$target" ]; then
    # Keep whatever is there (the stock file, or your edits to a copy).
    _run_at "$target" cp -p "$target" "$(_backup_path "$target")" || return 1
  fi
  _run_at "$target" install -m 644 "$src" "$target"
}

# The shell configs: .zshrc, .dircolors, .tmux.conf and the curated history.
# The basic and top sections both install zsh and tmux, so both call this.
# Your own files are backed up once, re-runs change nothing.
link_shell_configs() {
  step .zshrc link_config zsh/.zshrc "${HOME}/.zshrc"
  step .dircolors link_config .dircolors "${HOME}/.dircolors"
  # History is merged, not linked, so new commands stay out of the repo.
  step .zsh_history merge_history zsh/.zsh_history "${HOME}/.zsh_history"
  step .tmux.conf link_config tmux/.tmux.conf "${HOME}/.tmux.conf"
  # Reload only if a tmux server is running.
  if tmux info >/dev/null 2>&1; then
    step 'tmux reload' tmux source-file "${HOME}/.tmux.conf"
  fi
  step 'zsh from bash' start_zsh_from_bash
  return 0
}

# The git config of the dev section: delta as the pager, by one include of
# configs/git/dev.gitconfig in your ~/.gitconfig, and a global ignore file
# when you have none. Your own file is not replaced, but the include comes
# last, so it wins over a pager you set; delete the include line to undo it.
# Without delta nothing is included: git would fail to start its pager.
link_dev_git_config() {
  local conf="$HAKPAK_ROOT/configs/git/dev.gitconfig" ignore="$HAKPAK_ROOT/configs/git/gitignore"
  if [ "${HAKPAK_DRY_RUN:-0}" != "1" ] && ! has_command delta; then
    log "delta is not installed: leaving your git config alone"
    return 0
  fi
  has_command git || [ "${HAKPAK_DRY_RUN:-0}" = "1" ] || { echo "git is not installed"; return 1; }
  # A dry run reads nothing of yours: it records both steps.
  if [ "${HAKPAK_DRY_RUN:-0}" = "1" ]; then
    run_step git config --global --add include.path "$conf"
    run_step git config --global core.excludesFile "$ignore"
    return 0
  fi
  if git config --global --get-all include.path 2>/dev/null | grep -qxF -- "$conf"; then
    log_ok "git already includes $conf"
  else
    run_step git config --global --add include.path "$conf" || return 1
  fi
  if [ -z "$(git config --global --get core.excludesFile 2>/dev/null)" ]; then
    run_step git config --global core.excludesFile "$ignore" || return 1
  fi
}

# In a Docker Sandbox every shell, and Claude Code before each command it
# runs, sources /etc/sandbox-persistent.sh. One marked line there sources
# system/.dev, so the agent finds cargo, node, go and the uv tools, which a
# .zshrc alone would not give it. Added once, replaced if the clone moved.
_SBX_ENV_MARK='# hakpak: dev tools'
persist_dev_env_in_sbx() {
  local file="$HAKPAK_SYSROOT/etc/sandbox-persistent.sh" env="$HAKPAK_ROOT/system/.dev" line
  printf -v line '[ -r %q ] && . %q  %s' "$env" "$env" "$_SBX_ENV_MARK"
  if grep -qxF -- "$line" "$file" 2>/dev/null &&
      [ "$(grep -cF -- "$_SBX_ENV_MARK" "$file")" -eq 1 ]; then
    log_ok "$file already loads the dev environment"
    return 0
  fi
  # sed and sh, not a shell function: the file is root's, so they run under sudo.
  # shellcheck disable=SC2016 # $1 and $2 are for the inner sh
  _run_at "$file" sed -i "/${_SBX_ENV_MARK}\$/d" "$file" &&
    _run_at "$file" sh -c 'printf "%s\n" "$1" >> "$2"' sh "$line" "$file"
}

# The configs of the dev section: git, and in a sandbox its environment file.
# The shell part, system/.dev, needs no step: .zshrc sources every file in
# system/.
link_dev_configs() {
  step 'git config' link_dev_git_config
  if is_sbx; then
    step 'sandbox environment' persist_dev_env_in_sbx
  fi
  return 0
}

# What the dev section leaves to you: the Claude Code config (CLAUDE.md and
# language rules) is Trail of Bits' own, installed by a command in their
# repo, which the section cloned.
dev_hint() {
  local dir="$HAKPAK_OPT/claude-code-config"
  echo
  log_ok "For the Claude Code config (CLAUDE.md, language rules): cd $dir && claude, then run /trailofbits:config"
  if is_sbx; then
    echo "This is a sandbox: leave its settings.json unticked there. It denies sudo, and ~/.claude/settings.json here already holds the sandbox's own key helper and permission mode."
  fi
  echo "Open a new shell (or log out and in) to get the new PATH: cargo, node, pnpm and the uv tools."
}

# Make an interactive bash hand over to zsh, by sourcing
# configs/bash/start-zsh.bash from ~/.bashrc. The login shell is changed too
# (see _use_zsh_as_login_shell), but a container or sandbox shell starts bash
# directly and never reads it. One marked line is kept in ~/.bashrc: added
# once, replaced if the clone has moved, and a .bashrc that is your own link
# stays a link. HAKPAK_NO_ZSH=1 in your environment switches the hook off.
_ZSH_HOOK_MARK='# hakpak: start zsh'
start_zsh_from_bash() {
  local rc="${HOME}/.bashrc" hook="$HAKPAK_ROOT/configs/bash/start-zsh.bash" line
  [ -f "$hook" ] || { echo "no $hook"; return 1; }
  printf -v line '[ -r %q ] && . %q  %s' "$hook" "$hook" "$_ZSH_HOOK_MARK"
  if [ -f "$rc" ] && grep -qxF -- "$line" "$rc" &&
      [ "$(grep -cF -- "$_ZSH_HOOK_MARK" "$rc")" -eq 1 ]; then
    log_ok "$rc already starts zsh"
    return 0
  fi
  run_step _set_marked_line "$rc" "$_ZSH_HOOK_MARK" "$line"
}

# Keep exactly one line with <mark> in <file>: drop any there, add <line> at
# the end. The new text is written next to the file and moved over it, so a
# full disk or an interrupt leaves the old file whole; a link stays a link
# (the file it points to is the one replaced) and the mode is kept.
_set_marked_line() {
  local file="$1" mark="$2" line="$3" real tmp rc
  real="$file"
  [ -L "$file" ] && real="$(readlink -f "$file")"
  [ -n "$real" ] || { echo "can't resolve $file"; return 1; }
  tmp="$(mktemp "$real.hakpak.XXXXXXXX")" || return 1
  if [ -e "$real" ]; then
    chmod --reference="$real" "$tmp" || { rm -f "$tmp"; return 1; }
    grep -vF -- "$mark" "$real" > "$tmp"
    [ "$?" -le 1 ] || { rm -f "$tmp"; return 1; }
  else
    chmod 644 "$tmp"
  fi
  printf '%s\n' "$line" >> "$tmp" && mv -f "$tmp" "$real"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# The process group of a process, from /proc/<pid>/stat (the fifth field;
# the second, the name, may hold spaces and brackets).
_process_group() {
  local stat
  local -a f
  stat="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  read -r -a f <<< "${stat##*) }"
  [ -n "${f[2]:-}" ] || return 1
  echo "${f[2]}"
}

# The name of the interactive shell setup.sh was typed into (bash, sh, zsh),
# or nothing when it was started by anything else: a script, `bash -c`, a
# container entrypoint, ssh with a command. A shell with a prompt runs each
# command as a job in a process group of its own; a script's commands stay
# in the script's group.
_prompt_shell() {
  local name mine theirs
  if [ -n "${_HAKPAK_PROMPT_SHELL+x}" ]; then
    echo "$_HAKPAK_PROMPT_SHELL"
    return 0
  fi
  name="$(cat "/proc/$PPID/comm" 2>/dev/null)" || return 0
  mine="$(_process_group "$$")" || return 0
  theirs="$(_process_group "$PPID")" || return 0
  [ "$mine" != "$theirs" ] || return 0
  echo "${name#-}"
}

# Called last by setup.sh with the sections it installed: when zsh was among
# them (basic, top) and setup was typed at the prompt of another shell,
# replace setup with zsh, so the new shell is there without logging out.
# `exit` goes back to the shell setup was started from. Not in a dry run,
# not from a script, not when you already are in zsh, and not with
# HAKPAK_NO_ZSH=1. zsh gets your environment without the installer's own
# variables; the PATH and Go settings it needs come from its .zshrc.
start_zsh_now() {
  local zsh
  _toolset_known top "$@" || _toolset_known basic "$@" || return 0
  [ "${HAKPAK_DRY_RUN:-0}" != 1 ] || return 0
  [ -z "${HAKPAK_NO_ZSH:-}" ] || return 0
  [ -z "${HAKPAK_ZSH_STARTED:-}" ] || return 0
  if [ "${_HAKPAK_TTY:-0}" != 1 ]; then
    { [ -t 0 ] && [ -t 1 ]; } || return 0
  fi
  case "$(_prompt_shell)" in
    bash | sh | dash | ash | ksh | mksh | fish) ;;
    *) return 0 ;;
  esac
  zsh="$(command -v zsh)" || return 0
  "$zsh" -c exit >/dev/null 2>&1 || return 0
  log_ok "Starting zsh. Type exit to go back to your old shell; HAKPAK_NO_ZSH=1 keeps setup and bash from starting it."
  unset HAKPAK_ROOT HAKPAK_OPT HAKPAK_SYSROOT HAKPAK_TOOLSET
  HAKPAK_ZSH_STARTED=1 SHELL="$zsh" exec "$zsh" -l
}

# Add the curated zsh history to yours: merge_history <configs/path> <target>
# Your history is kept and stays last (so Ctrl+R finds your own commands
# first), curated entries you don't already have go before it, and nothing
# is duplicated. The result is your own file (mode 600), never a link into
# the repo, so new commands stay local. If the target is your own link to
# somewhere else (a synced folder), the file it points to is updated.
merge_history() {
  local src target="$2" real
  src="$(_config_source "$1")" || { echo "$src"; return 1; }
  if [ -L "$target" ]; then
    real="$(readlink -f "$target")"
    case "$real" in
      "$HAKPAK_ROOT"/*) ;;  # an older hakpak link into the repo: replace it
      *) target="$real" ;;
    esac
  fi
  run_step _merge_history_into "$src" "$target"
}

_merge_history_into() {
  local src="$1" target="$2" mine=/dev/null tmp
  [ -e "$target" ] && mine="$target"
  tmp="$(mktemp "$(dirname "$target")/.hakpak-history.XXXXXXXX")" || return 1
  # zsh extended history: an entry starts with ": <time>:<duration>;" and a
  # line ending in a backslash continues onto the next. Entries are compared
  # by their command, without the timestamp.
  if ! awk '
    function flush(   k) {
      if (entry == "") return
      k = entry
      sub(/^: [0-9]+:[0-9]+;/, "", k)
      if (from_mine) { have[k] = 1; own[++n_own] = entry }
      else if (!(k in have)) { have[k] = 1; new[++n_new] = entry }
      entry = ""
    }
    FNR == 1 { flush(); from_mine = (FILENAME == ARGV[1]); more = 0 }
    {
      if (more) entry = entry "\n" $0
      else { flush(); entry = $0 }
      more = ($0 ~ /\\$/)
    }
    END {
      flush()
      for (i = 1; i <= n_new; i++) print new[i]
      for (i = 1; i <= n_own; i++) print own[i]
    }
  ' "$mine" "$src" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" && mv -f "$tmp" "$target"
}

# True on WSL (1 or 2, any distro): its kernel release names Microsoft, or
# (for a custom WSL2 kernel) its interop handler is registered.
is_wsl() {
  grep -qi microsoft "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease" 2>/dev/null ||
    [ -e "$HAKPAK_SYSROOT/proc/sys/fs/binfmt_misc/WSLInterop" ]
}

# True inside a Docker Sandbox (sbx): it names itself in $SANDBOX_NAME and
# has the environment file every shell there sources.
is_sbx() {
  [ -n "${SANDBOX_NAME:-}" ] && [ -f "$HAKPAK_SYSROOT/etc/sandbox-persistent.sh" ]
}

# True if a wsl.conf turns on systemd: systemd=true under [boot], any case,
# spaces around the = allowed. False for a missing file.
wsl_conf_has_systemd() {
  awk '
    /^[[:space:]]*\[/ { boot = (tolower($0) ~ /^[[:space:]]*\[boot\][[:space:]]*$/); next }
    boot && tolower($0) ~ /^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$/ { on = 1 }
    END { exit !on }
  ' "$1" 2>/dev/null
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

# Make sure a command other installs rely on is there, installing its apt
# package (default: the same name) when it isn't: need_command <cmd> [package]
need_command() {
  has_command "$1" || apt_install "${2:-$1}"
}

apt_install() {
  run_step sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

_install_apt() {
  local name="$1" packages="${2:-$1}"
  # shellcheck disable=SC2086 # word-splitting the package list is intended
  apt_install $packages
}

_install_go() {
  local name="$1" module="$2"
  [ -n "$module" ] || { echo "go: missing module for $name"; return 1; }
  if [ -x "$GOPATH/bin/$name" ]; then
    log_ok "$name already installed"
    return 0
  fi
  # A fresh /opt is root's; make GOPATH yours so go install runs without sudo.
  ensure_dir "$GOPATH" &&
    run_step go install -v "$module"
}

_install_pipx() {
  local name="$1" spec="${2:-$1}"
  if has_command "$name"; then
    log_ok "$name already installed"
    return 0
  fi
  run_step pipx install "$spec"
}

_install_gem() {
  local name="$1" gem="${2:-$1}"
  if has_command "$name"; then
    log_ok "$name already installed"
    return 0
  fi
  run_step sudo gem install "$gem"
}

_install_git() {
  local name="$1" url="$2" dest="${3:-$HAKPAK_OPT/$1}"
  [ -n "$url" ] || { echo "git: missing url for $name"; return 1; }
  if [ -d "$dest/.git" ]; then
    log_ok "$name already cloned at $dest"
    return 0
  fi
  # Clone into an (empty) directory owned by you.
  need_command git &&
    ensure_dir "$dest" &&
    run_step git clone --depth 1 "$url" "$dest"
}

_install_venv() {
  local name="$1" url="$2" dest="$HAKPAK_OPT/$1"
  local done_marker="$dest/.venv/.hakpak-installed"
  _install_git "$name" "$url" "$dest" || return 1
  if [ -e "$done_marker" ]; then
    return 0
  fi
  run_step python3 -m venv "$dest/.venv" &&
    run_step "$dest/.venv/bin/pip" install -r "$dest/requirements.txt" &&
    run_step touch "$done_marker"
}

_install_url() {
  local name="$1" url="$2" dest="$3"
  if [ -z "$url" ] || [ -z "$dest" ]; then
    echo "url: $name needs a url and a destination"
    return 1
  fi
  if [ -e "$dest" ]; then
    log_ok "$name already downloaded"
    return 0
  fi
  ensure_dir "$(dirname "$dest")" &&
    run_step curl -fsSL -o "$dest" "$url"
}

# A Python command line tool in its own environment, with its command in
# ~/.local/bin. The package is the name unless given (ast-grep is
# ast-grep-cli on PyPI).
_install_uv() {
  local name="$1" package="${2:-$1}"
  if has_command "$name"; then
    log_ok "$name already installed"
    return 0
  fi
  run_step uv tool install "$package"
}

# True when Claude Code is there to run plugin commands. A dry run records
# them without it.
_need_claude() {
  [ "${HAKPAK_DRY_RUN:-0}" = "1" ] && return 0
  has_command claude && return 0
  echo "$1 needs Claude Code (the claude command); install the claude-code tool first"
  return 1
}

# A Claude Code plugin from a registered marketplace, for you in every
# project (user scope). Installing one you already have changes nothing.
# Both names end up in one argument of a command, so only plain names pass.
_install_plugin() {
  local name="$1" marketplace="${2:-}" part
  for part in "$name" "$marketplace"; do
    if ! [[ "$part" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      echo "plugin: needs a plain plugin name and marketplace name: $name@$marketplace"
      return 1
    fi
  done
  _need_claude "plugin $name" || return 1
  run_step claude plugin install "$name@$marketplace"
}

_install_custom() {
  local name="$1" fn="$2"
  declare -F "$fn" >/dev/null || { echo "custom: no function $fn for $name"; return 1; }
  "$fn"
}

# --- vendor downloads ---

# Check <file> against a sha256 manifest. With <asset>, the manifest has
# "<hash>  <asset>" lines (sha256sum format) and the line for exactly that
# asset is used. Without it, the manifest holds only the hash (kubectl.sha256).
# A missing entry is a failure, not a skipped check.
verify_sha256() {
  local file="$1" sums="$2" asset="${3:-}" expected actual
  if [ -n "$asset" ]; then
    expected="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$sums")"
    # A checksum file for a single asset may hold only the hash, no name.
    [ -n "$expected" ] ||
      expected="$(awk 'NF { n++; if (NF == 1) h = $1 } END { if (n == 1) print h }' "$sums")"
  else
    expected="$(awk 'NF { print $1; exit }' "$sums")"
  fi
  if ! [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "no checksum for ${asset:-$(basename "$file")} in $(basename "$sums")"
    return 1
  fi
  actual="$(sha256sum "$file" | awk '{ print $1 }')" || return 1
  if [ "${expected,,}" != "$actual" ]; then
    echo "checksum mismatch for ${asset:-$(basename "$file")}"
    return 1
  fi
}

# Check a detached signature: verify_gpg_signature <key.asc> <sig> <file>
# Only the given key is trusted (gpgv with a keyring made from it, and its
# home in the private dir next to the signature), never your own keyring.
verify_gpg_signature() {
  local key="$1" sig="$2" file="$3" keyring
  keyring="$(cd "$(dirname "$sig")" && pwd)/hakpak-verify.gpg"
  gpg --batch --yes --dearmor -o "$keyring" < "$key" &&
    GNUPGHOME="$(dirname "$keyring")" gpgv --keyring "$keyring" "$sig" "$file"
}

# Copy a downloaded key to <out> as a binary keyring, dearmoring it if it's
# ASCII-armored. Fails when it isn't an OpenPGP key (an HTML error page).
_dearmor_key() {
  local in="$1" out="$2"
  if grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$in"; then
    gpg --batch --yes --dearmor -o "$out" < "$in" || return 1
  else
    cp "$in" "$out" || return 1
  fi
  gpg --batch --homedir "$(dirname "$out")" --show-keys "$out" >/dev/null 2>&1 || {
    echo "not an OpenPGP key: $in"
    return 1
  }
}

# True when the key file <file> holds exactly one OpenPGP key and its
# fingerprint is <fingerprint> (spaces and letter case don't matter):
#   _key_has_fingerprint <file> <fingerprint>
_key_has_fingerprint() {
  local file="$1" want="${2//[[:space:]]/}" got home
  # gpg needs a home it can write, even to only show a key.
  home="$(mktemp -d "${TMPDIR:-/tmp}/hakpak.XXXXXXXX")" || return 1
  got="$(gpg --batch --homedir "$home" --with-colons --show-keys "$file" 2>/dev/null |
    awk -F: '$1 == "pub" { primary = 1 } $1 == "fpr" && primary { print $10; primary = 0 }')"
  rm -rf "$home"
  if [ -z "$got" ]; then
    echo "not an OpenPGP key: $file"
    return 1
  fi
  if [ "${got^^}" != "${want^^}" ]; then
    echo "key fingerprint is not $want:"
    echo "$got"
    return 1
  fi
}

_write_line() {
  printf '%s\n' "$1" > "$2"
}

# Add a vendor apt repo signed by its own key:
#   add_apt_repo <name> <key-url> <keyring> <source line> [fingerprint]
# The key is downloaded to a temp dir and installed at <keyring> (no
# apt-key). With a fingerprint, the download must be exactly that one key,
# or nothing is installed, and a keyring that is already there is checked
# too and replaced if it holds another key. The source line, which must say signed-by=<keyring>, goes in
# /etc/apt/sources.list.d/<name>.list. Then only that list is refreshed. A
# repo whose list and keyring are both there already is skipped. If apt
# can't read the new repo, its list is removed again so apt keeps working.
add_apt_repo() {
  local name="$1" key_url="$2" keyring="$3" line="$4" fingerprint="${5:-}"
  local key list tmp rc
  if ! [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "apt repo name must be a plain file name: $name"
    return 1
  fi
  case "$keyring" in
    /*) ;;
    *) echo "apt repo $name: keyring must be an absolute path: $keyring"; return 1 ;;
  esac
  case "$line" in
    *"signed-by=$keyring"[\ \]]*) ;;
    *) echo "apt repo $name: source line must use signed-by=$keyring"; return 1 ;;
  esac
  key="$HAKPAK_SYSROOT$keyring"
  list="$HAKPAK_SYSROOT/etc/apt/sources.list.d/$name.list"
  if [ -f "$list" ] && [ -s "$key" ] && [ -z "$fingerprint" ]; then
    log_ok "$name apt repo already configured"
    return 0
  fi
  if ! has_command gpg; then
    apt_install gnupg || return 1
  fi
  if [ -f "$list" ] && [ -s "$key" ]; then
    if _key_has_fingerprint "$key" "$fingerprint" >/dev/null; then
      log_ok "$name apt repo already configured"
      return 0
    fi
    echo "$name apt repo: $key is not the expected key, replacing it"
  fi
  need_command curl || return 1
  tmp="$(make_temp_dir)" || return 1
  run_step curl -fsSL -o "$tmp/$name.key" "$key_url" &&
    run_step _dearmor_key "$tmp/$name.key" "$tmp/$name.gpg" &&
    { [ -z "$fingerprint" ] || run_step _key_has_fingerprint "$tmp/$name.gpg" "$fingerprint"; } &&
    run_step _write_line "$line" "$tmp/$name.list" &&
    _run_at "$key" install -d -m 755 "$(dirname "$key")" &&
    _run_at "$key" install -m 644 "$tmp/$name.gpg" "$key" &&
    _run_at "$list" install -d -m 755 "$(dirname "$list")" &&
    _run_at "$list" install -m 644 "$tmp/$name.list" "$list"
  rc=$?
  run_step rm -rf "$tmp"
  [ "$rc" -eq 0 ] || return "$rc"
  if ! run_step sudo apt-get update -o "Dir::Etc::sourcelist=$list" \
      -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0; then
    echo "apt can't read the $name repo; removing $list"
    _run_at "$list" rm -f "$list"
    return 1
  fi
}

install_tool() {
  local kind="$1" name="$2"
  shift 2
  case "$kind" in
    apt|go|pipx|gem|git|venv|url|uv|plugin|custom) ;;
    *)
      echo "unknown tool kind: $kind ($name)"
      HAKPAK_FAILED+=("$name")
      return 1
      ;;
  esac
  log "Installing $name"
  if "_install_$kind" "$name" "$@"; then
    return 0
  fi
  echo "failed: $name"
  HAKPAK_FAILED+=("$name")
  return 1
}

# The Toolset manifest (install_section) and the custom install steps.
# shellcheck source=install/toolset.sh
source "$HAKPAK_ROOT/install/toolset.sh"
# shellcheck source=install/custom.sh
source "$HAKPAK_ROOT/install/custom.sh"

install_summary() {
  if [ "${#HAKPAK_FAILED[@]}" -eq 0 ]; then
    log_ok "All tools installed"
    return 0
  fi
  log "Failed to install: ${HAKPAK_FAILED[*]}"
  if is_sbx; then
    # The name goes into a command to copy: print it only when it is plain.
    local box="SANDBOX"
    [[ "$SANDBOX_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && box="$SANDBOX_NAME"
    echo "This is a sandbox: a failed download is often its network policy (an HTTP 403)."
    echo "On the host, see what was blocked and allow the host you need, then run this section again:"
    echo "  sbx policy log $box"
    echo "  sbx policy allow network --sandbox $box HOST"
  fi
  return 1
}
