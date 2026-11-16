#!/usr/bin/env bash
# Reads the Toolset manifest (install/toolset.txt). Sourced by lib.sh, and by
# tools/gen-readme to render the README tool list.
#
#   toolset_rows [section]   one tab-separated line per tool:
#                            section, kind, name, source, note
#   toolset_check            report every problem in the manifest
#   install_section <id>     install_tool every row of one section (lib.sh),
#                            or only the tools in HAKPAK_TOOLS when it is set
#   tool_wanted <name>       true unless HAKPAK_TOOLS is set without <name>
#   toolset_plan <tool...>   which section installs each ticked tool
#
# Manifest rows are whitespace-separated: section kind name [source...]
# A `#` at the start of a line, or after a space, starts a comment; on a tool
# row that comment is the tool's note in the README. In the source, `$HOME`
# and `$HAKPAK_OPT` are replaced with their values and nothing else is
# expanded.

HAKPAK_TOOLSET="${HAKPAK_TOOLSET:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolset.txt}"

# Sections in install and README order, as <id>:<README title>.
HAKPAK_SECTIONS=(
  "top:Top"
  "dev:Dev"
  "ai:AI"
  "network:Network"
  "environment:Environment"
  "basic:Basic"
  "surfing:Surfing"
  "web:Web Tools"
  "pentest:Pentest Tools"
  "cloud:Cloud"
  "cicd:CI/CD"
  "mitm:MiTM"
  "wordlists:Wordlists"
  "wsl:WSL config"
  "rdp:RDP"
)

HAKPAK_KINDS=(apt go pipx gem git venv url uv plugin custom)

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
  local -A seen=() where=() how=()
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
      plugin) [ "${#src_args[@]}" -ge 1 ] || errs+=("line $n: $name: plugin needs a marketplace") ;;
      custom)
        if [ "${#src_args[@]}" -lt 1 ]; then
          errs+=("line $n: $name: custom needs a function name")
        elif ! declare -F "${src_args[0]}" >/dev/null; then
          errs+=("line $n: $name: no function ${src_args[0]}")
        fi
        ;;
    esac
    # One row per tool in a section. A tool may be in more than one
    # section, with the same kind and source in each.
    if [ -n "${seen[$section/$name]:-}" ]; then
      errs+=("line $n: $name listed twice in $section (also line ${seen[$section/$name]})")
    elif [ -n "${where[$name]:-}" ] && [ "${how[$name]}" != "$kind $src" ]; then
      errs+=("line $n: $name: not the same as in ${where[$name]}")
    fi
    seen[$section/$name]="$n"
    if [ -z "${where[$name]:-}" ]; then
      where[$name]="$section (line $n)"
      how[$name]="$kind $src"
    fi
  done <<< "$rows"
  [ "${#errs[@]}" -eq 0 ] && return 0
  printf 'toolset %s\n' "${errs[@]}"
  return 1
}

# HAKPAK_TOOLS, when set, is the space-separated list of the tools a section
# installs (setup.sh sets it from the menu and its plan); unset, it is all
# of them. Section scripts also ask it before putting a tool's configs in
# place.
tool_wanted() {
  [ -z "${HAKPAK_TOOLS+x}" ] && return 0
  [[ " $HAKPAK_TOOLS " == *" $1 "* ]]
}

# The install plan for a set of ticked tools: one line per section that
# installs any, "<section><TAB><tools>", in install order, its tools in
# manifest order. A tool listed in several sections is installed once, by
# the section with the largest share of its tools ticked (a tie goes to the
# section installed first), so ticking all of top brings Claude Code with
# top, not with dev or ai. A section whose ticked tools all come with
# another is left out. A ticked tool brings the tools it needs (_toolset_needs)
# when its own section lists them, ticked or not, and they are installed
# no later than it.
toolset_plan() {
  local rows section kind name n i owner best_on best_total id p
  local -A ticked=() total=() on=() owner_of=() listed=() pos=()
  local -a ids=() order=()
  for name in "$@"; do ticked[$name]=1; done
  rows="$(toolset_rows "")" || return 1
  for i in "${HAKPAK_SECTIONS[@]}"; do ids+=("${i%%:*}"); done
  for i in "${!ids[@]}"; do pos[${ids[i]}]=$i; done
  while IFS=$'\t' read -r section _ name _; do
    [ -n "$name" ] && listed[$section/$name]=1
  done <<< "$rows"
  # Prerequisites listed in the same section come along (twice: a plugin
  # needs the marketplaces, which need claude-code).
  for _ in 1 2; do
    while IFS=$'\t' read -r section kind name _; do
      [ -n "${ticked[$name]:-}" ] || continue
      for p in $(_toolset_needs "$kind" "$name"); do
        [ -n "${listed[$section/$p]:-}" ] && ticked[$p]=1
      done
    done <<< "$rows"
  done
  while IFS=$'\t' read -r section _ name _; do
    [ -n "$name" ] || continue
    total[$section]=$((${total[$section]:-0} + 1))
    [ -n "${ticked[$name]:-}" ] && on[$section]=$((${on[$section]:-0} + 1))
  done <<< "$rows"
  # Owners: compare on/total as on_a * total_b > on_b * total_a.
  for id in "${ids[@]}"; do
    while IFS=$'\t' read -r section _ name _; do
      [ "$section" = "$id" ] && [ -n "${ticked[$name]:-}" ] || continue
      owner="${owner_of[$name]:-}"
      if [ -z "$owner" ]; then
        owner_of[$name]="$id"
        continue
      fi
      best_on=${on[$owner]} best_total=${total[$owner]}
      if [ $((on[$id] * best_total)) -gt $((best_on * total[$id])) ]; then
        owner_of[$name]="$id"
      fi
    done <<< "$rows"
  done
  # A prerequisite goes no later than a section that installs a tool
  # needing it, if that section lists it.
  for _ in 1 2 3; do
    while IFS=$'\t' read -r section kind name _; do
      [ -n "${ticked[$name]:-}" ] && [ "${owner_of[$name]}" = "$section" ] || continue
      for p in $(_toolset_needs "$kind" "$name"); do
        [ -n "${owner_of[$p]:-}" ] && [ -n "${listed[$section/$p]:-}" ] || continue
        [ "${pos[${owner_of[$p]}]}" -gt "${pos[$section]}" ] && owner_of[$p]="$section"
      done
    done <<< "$rows"
  done
  for id in "${ids[@]}"; do
    order=()
    while IFS=$'\t' read -r section _ name _; do
      [ "$section" = "$id" ] && [ "${owner_of[$name]:-}" = "$id" ] && order+=("$name")
    done <<< "$rows"
    n=${#order[@]}
    [ "$n" -gt 0 ] && printf '%s\t%s\n' "$id" "${order[*]}"
  done
  return 0
}

# The tools a tool needs installed first: _toolset_needs <kind> <name>
_toolset_needs() {
  case "$1" in
    go) echo go ;;
    uv) echo uv ;;
    plugin) echo claude-code claude-marketplaces ;;
  esac
  case "$2" in
    python) echo uv ;;
    node) echo fnm ;;
    claude-marketplaces) echo claude-code ;;
  esac
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
  if [ -n "${HAKPAK_TOOLS+x}" ]; then
    local -a picked=()
    for row in "${rows[@]}"; do
      IFS="$_TS" read -r _ _ _ name _ <<< "$row"
      tool_wanted "$name" && picked+=("$row")
    done
    if [ "${#picked[@]}" -eq 0 ]; then
      log_ok "Section $id: nothing ticked here"
      return 0
    fi
    rows=("${picked[@]}")
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
      # apt_install already retried a mismatch for the whole group.
      local _HAKPAK_APT_NO_RETRY=1
      for i in "${!apt_names[@]}"; do
        read -r -a src_args <<< "${apt_args[$i]}"
        args=()
        for a in "${src_args[@]}"; do args+=("$(_toolset_expand "$a")"); done
        install_tool apt "${apt_names[$i]}" "${args[*]}" || true
      done
      unset _HAKPAK_APT_NO_RETRY
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
