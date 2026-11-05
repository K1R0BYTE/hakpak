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
#   add_apt_repo <name> <key-url> <keyring> <source line>   signed vendor apt repo
#   verify_sha256 <file> <sums> [asset]                      check a download's hash
#   verify_gpg_signature <key.asc> <sig> <file>              check a detached signature
# Call the verify_* checks through run_step, so a dry run records them.
#
# Adapters: every side-effecting command goes through `run_step`. Normally it
# executes; with HAKPAK_DRY_RUN=1 it records the command (one shell-quoted
# line per command) to $HAKPAK_DRY_RUN_LOG, or stdout, and changes nothing.

HAKPAK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HAKPAK_OPT="${HAKPAK_OPT:-/opt}"
# Prefix for /etc targets of link_config. Empty on a real install; tests
# point it at a temp dir.
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
# link_config and merge_history are called directly: they send their own
# commands through run_step, so a dry run records what they would do.
step() {
  local label="$1" rc
  shift
  case "$1" in
    link_config|merge_history) "$@" ;;
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

_copy_config() {
  local src="$1" target="$2"
  if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$src" "$target"; then
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

# --- vendor downloads ---

# Check <file> against a sha256 manifest. With <asset>, the manifest has
# "<hash>  <asset>" lines (sha256sum format) and the line for exactly that
# asset is used. Without it, the manifest holds only the hash (kubectl.sha256).
# A missing entry is a failure, not a skipped check.
verify_sha256() {
  local file="$1" sums="$2" asset="${3:-}" expected actual
  if [ -n "$asset" ]; then
    expected="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1; exit }' "$sums")"
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

_write_line() {
  printf '%s\n' "$1" > "$2"
}

# Add a vendor apt repo signed by its own key:
#   add_apt_repo <name> <key-url> <keyring> <source line>
# The key is downloaded to a temp dir and installed at <keyring> (no
# apt-key); the source line, which must say signed-by=<keyring>, goes in
# /etc/apt/sources.list.d/<name>.list. Then only that list is refreshed. A
# repo whose list and keyring are both there already is skipped. If apt
# can't read the new repo, its list is removed again so apt keeps working.
add_apt_repo() {
  local name="$1" key_url="$2" keyring="$3" line="$4"
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
  if [ -f "$list" ] && [ -s "$key" ]; then
    log_ok "$name apt repo already configured"
    return 0
  fi
  if ! has_command gpg; then
    apt_install gnupg || return 1
  fi
  tmp="$(make_temp_dir)" || return 1
  run_step curl -fsSL -o "$tmp/$name.key" "$key_url" &&
    run_step _dearmor_key "$tmp/$name.key" "$tmp/$name.gpg" &&
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
  return 1
}
