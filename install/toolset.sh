#!/usr/bin/env bash
# Reads the Toolset manifest (install/toolset.txt). Sourced by lib.sh, and by
# tools/gen-readme to render the README tool list.
#
#   toolset_rows [section]   one tab-separated line per tool:
#                            section, kind, name, source, note
#   toolset_check            report every problem in the manifest
#   install_section <id>     install_tool every row of one section (lib.sh)
#
# Manifest rows are whitespace-separated: section kind name [source...]
# A `#` at the start of a line, or after a space, starts a comment; on a tool
# row that comment is the tool's note in the README. In the source, `$HOME`
# and `$HAKPAK_OPT` are replaced with their values and nothing else is
# expanded.

HAKPAK_TOOLSET="${HAKPAK_TOOLSET:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolset.txt}"

# Sections in install and README order, as <id>:<README title>.
HAKPAK_SECTIONS=(
  "system:System"
  "environment:Environment"
  "basic:Basic"
  "surfing:Surfing"
  "web:Web Tools"
  "pentest:Pentest Tools"
  "cloud:Cloud"
  "cicd:CI/CD"
  "mitm:MiTM"
  "wordlists:Wordlists"
  "rdp:RDP"
)

HAKPAK_KINDS=(apt go pipx gem git venv url custom)

# Field separator for the internal row format. Not tab: `read` collapses
# runs of whitespace separators, which would drop empty fields.
_TS=$'\x1f'

# Prints: line number, section, kind, name, source, note (separated by $_TS)
# for every non-empty row, including broken ones; toolset_check judges them.
_toolset_parse() {
  local n=0 line body note
  local -a f
  [ -r "$HAKPAK_TOOLSET" ] || { echo "toolset: can't read $HAKPAK_TOOLSET" >&2; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line//$'\r'/}"
    case "$line" in
      [[:space:]]*'#'* | '#'*)
        # A line that is only a comment (maybe indented).
        body="${line%%#*}"
        [ -z "${body//[[:space:]]/}" ] && continue
        ;;
    esac
    body="${line%%[[:space:]]#*}"
    note="${line#"$body"}"
    note="${note#*#}"
    note="${note#"${note%%[![:space:]]*}"}"
    note="${note%"${note##*[![:space:]]}"}"
    read -r -a f <<< "$body"
    [ "${#f[@]}" -eq 0 ] && continue
    printf "%s$_TS%s$_TS%s$_TS%s$_TS%s$_TS%s\n" "$n" "${f[0]}" "${f[1]:-}" "${f[2]:-}" "${f[*]:3}" "$note"
  done < "$HAKPAK_TOOLSET"
}

# Rows of one section (or all), in manifest order, still in $_TS format.
_toolset_select() {
  local want="${1:-}" rows n section rest
  rows="$(_toolset_parse)" || return 1
  [ -n "$rows" ] || return 0
  while IFS="$_TS" read -r n section rest; do
    if [ -z "$want" ] || [ "$section" = "$want" ]; then
      printf "%s$_TS%s$_TS%s\n" "$n" "$section" "$rest"
    fi
  done <<< "$rows"
}

toolset_rows() {
  local rows row
  rows="$(_toolset_select "${1:-}")" || return 1
  [ -n "$rows" ] || return 0
  # Drop the line number; separate fields with tabs.
  while IFS= read -r row; do
    row="${row#*"$_TS"}"
    printf '%s\n' "${row//$_TS/$'\t'}"
  done <<< "$rows"
}

_toolset_known() {
  local want="$1" item
  shift
  for item in "$@"; do
    [ "$item" = "$want" ] && return 0
  done
  return 1
}

toolset_check() {
  local rows n section kind name src _note
  local -a ids=() src_args errs=()
  local -A seen=()
  local s
  for s in "${HAKPAK_SECTIONS[@]}"; do ids+=("${s%%:*}"); done
  rows="$(_toolset_parse)" || return 1
  [ -n "$rows" ] || { echo "toolset: $HAKPAK_TOOLSET has no tools"; return 1; }
  while IFS="$_TS" read -r n section kind name src _note; do
    if [ -z "$name" ]; then
      errs+=("line $n: needs a section, a kind and a name")
      continue
    fi
    _toolset_known "$section" "${ids[@]}" || errs+=("line $n: $name: unknown section: $section")
    if ! _toolset_known "$kind" "${HAKPAK_KINDS[@]}"; then
      errs+=("line $n: $name: unknown kind: $kind")
      continue
    fi
    read -r -a src_args <<< "$src"
    case "$kind" in
      go) [ "${#src_args[@]}" -ge 1 ] || errs+=("line $n: $name: go needs a module@version") ;;
      git|venv) [ "${#src_args[@]}" -ge 1 ] || errs+=("line $n: $name: $kind needs a url") ;;
      url) [ "${#src_args[@]}" -ge 2 ] || errs+=("line $n: $name: url needs a url and a destination") ;;
      custom)
        if [ "${#src_args[@]}" -lt 1 ]; then
          errs+=("line $n: $name: custom needs a function name")
        elif ! declare -F "${src_args[0]}" >/dev/null; then
          errs+=("line $n: $name: no function ${src_args[0]}")
        fi
        ;;
    esac
    if [ -n "${seen[$name]:-}" ]; then
      errs+=("line $n: $name listed twice (also line ${seen[$name]})")
    else
      seen[$name]="$n"
    fi
  done <<< "$rows"
  [ "${#errs[@]}" -eq 0 ] && return 0
  printf 'toolset %s\n' "${errs[@]}"
  return 1
}

# Replace $HOME and $HAKPAK_OPT in one source field. Nothing else expands.
# The replacements are quoted so an `&` in them stays literal (bash 5.2).
_toolset_expand() {
  local s="$1"
  s="${s//\$HAKPAK_OPT/"$HAKPAK_OPT"}"
  s="${s//\$HOME/"$HOME"}"
  printf '%s' "$s"
}

# Install every row of one section. Its apt tools go first, in one apt-get
# call; if that fails, each is tried on its own so only the bad ones are
# reported. The other tools follow in manifest order.
install_section() {
  local id="$1" row kind name src a i
  local -a rows args src_args apt_names=() apt_args=() other=() packages=()
  if ! toolset_check; then
    echo "toolset: fix $HAKPAK_TOOLSET first"
    HAKPAK_FAILED+=("toolset")
    return 1
  fi
  # Read every row before installing: install commands may read stdin.
  mapfile -t rows < <(_toolset_select "$id")
  if [ "${#rows[@]}" -eq 0 ]; then
    echo "toolset: no tools in section $id"
    HAKPAK_FAILED+=("section $id")
    return 1
  fi
  for row in "${rows[@]}"; do
    IFS="$_TS" read -r _ _ kind name src _ <<< "$row"
    if [ "$kind" = apt ]; then
      apt_names+=("$name")
      apt_args+=("$src")
      read -r -a src_args <<< "${src:-$name}"
      for a in "${src_args[@]}"; do packages+=("$(_toolset_expand "$a")"); done
    else
      other+=("$row")
    fi
  done
  if [ "${#apt_names[@]}" -gt 0 ]; then
    log "Installing ${apt_names[*]}"
    if apt_install "${packages[@]}"; then
      log_ok "Installed ${apt_names[*]}"
    else
      for i in "${!apt_names[@]}"; do
        read -r -a src_args <<< "${apt_args[$i]}"
        args=()
        for a in "${src_args[@]}"; do args+=("$(_toolset_expand "$a")"); done
        install_tool apt "${apt_names[$i]}" "${args[*]}" || true
      done
    fi
  fi
  for row in "${other[@]}"; do
    IFS="$_TS" read -r _ _ kind name src _ <<< "$row"
    args=()
    read -r -a src_args <<< "$src"
    for a in "${src_args[@]}"; do args+=("$(_toolset_expand "$a")"); done
    install_tool "$kind" "$name" "${args[@]}" || true
  done
  return 0
}
