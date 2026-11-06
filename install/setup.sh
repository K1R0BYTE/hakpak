#!/usr/bin/env bash
# hakpak setup: tick sections in a menu, or name them as arguments.
#
#   setup.sh                         open the menu and tick the sections to install
#   setup.sh web pentest             only those sections (still in install order)
#   setup.sh all                     every section, in install order
#   setup.sh --dry-run [section...]  print what would run, change nothing
#   setup.sh --no-wsl-conf ...       on WSL, leave /etc/wsl.conf alone
#
# On WSL, /etc/wsl.conf is installed first, whatever sections are chosen
# (--no-wsl-conf skips it).
# Each section is one script in install/ (see CONTEXT.md). A failing section
# doesn't stop the next; setup lists the failed sections and exits non-zero.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The script that installs each section.
section_script() {
  case "$1" in
    system) echo system.sh ;;
    environment) echo enviroment.sh ;;
    basic) echo basic.sh ;;
    surfing) echo surfing.sh ;;
    web) echo web-soft.sh ;;
    pentest) echo pentest-soft.sh ;;
    cloud) echo cloud.sh ;;
    cicd) echo cicd.sh ;;
    mitm) echo mitm.sh ;;
    wordlists) echo wordlists.sh ;;
    rdp) echo rdp.sh ;;
    *) return 1 ;;
  esac
}

section_ids() {
  local s
  for s in "${HAKPAK_SECTIONS[@]}"; do echo "${s%%:*}"; done
}

usage() {
  echo "Usage: setup.sh [section...|all] [--dry-run]"
  echo
  echo "With no sections, a menu opens to tick the sections to install."
  echo "'all' installs every section. Sections:"
  local s
  for s in "${HAKPAK_SECTIONS[@]}"; do
    printf '  %-12s %s\n' "${s%%:*}" "${s#*:}"
  done
  echo
  echo "  --dry-run      print what would run, change nothing"
  echo "  --no-wsl-conf  on WSL, leave /etc/wsl.conf as it is"
  echo "  -h, --help     show this help"
}

wanted=()
all=0
wsl_conf=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) export HAKPAK_DRY_RUN=1 ;;
    --no-wsl-conf) wsl_conf=0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $arg"; echo; usage; exit 2 ;;
    all) all=1 ;;
    *)
      if ! section_script "$arg" >/dev/null; then
        echo "unknown section: $arg"
        echo "valid sections: $(section_ids | paste -sd' ') all"
        exit 2
      fi
      wanted+=("$arg")
      ;;
  esac
done

[ "$all" = 1 ] && mapfile -t wanted < <(section_ids)

# The menu needs a terminal: never read piped or redirected input as keys.
if [ "${#wanted[@]}" -eq 0 ] && [ ! -t 0 ] && [ "${_HAKPAK_MENU_TTY:-0}" != 1 ]; then
  echo "No terminal for the section menu: pass section names or all"
  echo "valid sections: $(section_ids | paste -sd' ') all"
  exit 2
fi

# The section menu: one checkbox per section, read key by key from stdin.
# j/k or arrows move, space ticks, a ticks or unticks all, Enter installs,
# q quits. Sets `wanted` to the ticked ids; returns 1 if nothing is installed.
choose_sections() {
  local ids=() names=() s i cur=0 key rest note="" drawn=0 lines
  mapfile -t ids < <(section_ids)
  for s in "${HAKPAK_SECTIONS[@]}"; do names+=("${s#*:}"); done
  local n=${#ids[@]} ticked=()
  for ((i = 0; i < n; i++)); do ticked[i]=0; done
  lines=$((n + 3))
  while true; do
    # On a terminal, draw over the last frame instead of below it.
    if [ "$drawn" = 1 ] && [ -t 1 ]; then printf '\033[%dA\033[J' "$lines"; fi
    drawn=1
    echo "Arrows or j/k move, space ticks, a ticks all, Enter installs, q quits"
    for ((i = 0; i < n; i++)); do
      local box="[ ]" mark=" "
      [ "${ticked[i]}" = 1 ] && box="[x]"
      [ "$i" = "$cur" ] && mark=">"
      printf '%s %s %-12s %s\n' "$mark" "$box" "${ids[i]}" "${names[i]}"
    done
    echo
    echo "$note"
    note=""
    IFS= read -rsn1 key || { echo "Nothing installed"; return 1; }
    if [ "$key" = $'\033' ]; then
      IFS= read -rsn2 -t 1 rest || true
      case "$rest" in
        "[A" | OA) key=k ;;
        "[B" | OB) key=j ;;
        *) continue ;;
      esac
    fi
    case "$key" in
      k) [ "$cur" -gt 0 ] && cur=$((cur - 1)) ;;
      j) [ "$cur" -lt $((n - 1)) ] && cur=$((cur + 1)) ;;
      " ") ticked[cur]=$((1 - ticked[cur])) ;;
      a)
        local v=1
        [[ " ${ticked[*]} " != *" 0 "* ]] && v=0
        for ((i = 0; i < n; i++)); do ticked[i]=$v; done
        ;;
      q) echo "Nothing installed"; return 1 ;;
      "")
        wanted=()
        for ((i = 0; i < n; i++)); do
          [ "${ticked[i]}" = 1 ] && wanted+=("${ids[i]}")
        done
        [ "${#wanted[@]}" -gt 0 ] && return 0
        note="Tick at least one section with space, or press q to quit"
        ;;
    esac
  done
}

require_normal_user

echo -e "${_RED}
██╗  ██╗ █████╗ ██╗  ██╗██████╗  █████╗ ██╗  ██╗
██║  ██║██╔══██╗██║ ██╔╝██╔══██╗██╔══██╗██║ ██╔╝
███████║███████║█████╔╝ ██████╔╝███████║█████╔╝
██╔══██║██╔══██║██╔═██╗ ██╔═══╝ ██╔══██║██╔═██╗
██║  ██║██║  ██║██║  ██╗██║     ██║  ██║██║  ██╗
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝
${_NOCOLOR}"
if [ "${HAKPAK_DRY_RUN:-0}" = "1" ]; then
  log_ok "Dry run: nothing is installed or changed"
fi

if [ "${#wanted[@]}" -eq 0 ]; then
  choose_sections || exit 1
fi

# Install order, whatever order the sections were named in; each runs once.
selected=()
while IFS= read -r id; do
  if _toolset_known "$id" "${wanted[@]}"; then
    selected+=("$id")
  fi
done < <(section_ids)

failed=()
# On WSL, /etc/wsl.conf goes in whatever sections are chosen, unless
# --no-wsl-conf. A file that is already there is backed up first.
wsl_failed=0
if [ "$wsl_conf" = 1 ] && is_wsl; then
  echo "== WSL config"
  install_wsl_conf || wsl_failed=1
fi

for id in "${selected[@]}"; do
  echo "== Section: $id"
  bash "$HAKPAK_ROOT/install/$(section_script "$id")" || failed+=("$id")
done

echo
if [ "$wsl_failed" = 1 ]; then
  log "Failed: /etc/wsl.conf"
fi
if [ "${#failed[@]}" -gt 0 ]; then
  log "Failed sections: ${failed[*]}"
fi
if [ "$wsl_failed" = 1 ] || [ "${#failed[@]}" -gt 0 ]; then
  exit 1
fi
log_ok "Done: ${selected[*]}"
