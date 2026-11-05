#!/usr/bin/env bash
# hakpak install module. Source it from a section script:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#   install_tool apt  nmap
#   install_tool go   ffuf github.com/ffuf/ffuf/v2@latest
#   install_summary
#
# Tool kinds (see CONTEXT.md):
#   apt    <name> [packages]          apt-get install (packages default to name)
#   go     <name> <module@version>    go install into $GOPATH (skips if the binary exists)
#   pipx   <name> [spec]              pipx install (skips if the command exists)
#   gem    <name> [gem]               gem install (skips if the command exists)
#   git    <name> <url> [dest]        shallow clone to dest, default $HAKPAK_OPT/<name>
#   venv   <name> <url>               git clone + .venv + pip install -r requirements.txt
#   url    <name> <url> <dest>        download one file (skips if dest exists)
#   custom <name> <function>          call a function that uses `run_step` for its commands
#
# One failing tool doesn't stop the section; install_summary lists the
# failures and returns non-zero.
#
# Adapters: every side-effecting command goes through `run_step`. Normally it
# executes; with HAKPAK_DRY_RUN=1 it records the command (one shell-quoted
# line per command) to $HAKPAK_DRY_RUN_LOG, or stdout, and changes nothing.

HAKPAK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HAKPAK_OPT="${HAKPAK_OPT:-/opt}"
export HAKPAK_ROOT HAKPAK_OPT

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
step() {
  local label="$1"
  shift
  if run_step "$@"; then
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
  local dir="$1" parent="$1"
  while [ ! -e "$parent" ]; do
    parent="$(dirname "$parent")"
  done
  if [ -w "$parent" ]; then
    run_step mkdir -p "$dir"
  else
    run_step sudo mkdir -p "$dir" &&
      run_step sudo chown "$(id -un):$(id -gn)" "$dir"
  fi
}

has_command() {
  command -v "$1" >/dev/null 2>&1
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

_install_custom() {
  local name="$1" fn="$2"
  declare -F "$fn" >/dev/null || { echo "custom: no function $fn for $name"; return 1; }
  "$fn"
}

install_tool() {
  local kind="$1" name="$2"
  shift 2
  case "$kind" in
    apt|go|pipx|gem|git|venv|url|custom) ;;
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

install_summary() {
  if [ "${#HAKPAK_FAILED[@]}" -eq 0 ]; then
    log_ok "All tools installed"
    return 0
  fi
  log "Failed to install: ${HAKPAK_FAILED[*]}"
  return 1
}
