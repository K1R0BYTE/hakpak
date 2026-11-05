#!/usr/bin/env bash
# hakpak setup: install every section, or only the ones you name.
#
#   setup.sh                         every section, in install order
#   setup.sh web pentest             only those sections (still in install order)
#   setup.sh --dry-run [section...]  print what would run, change nothing
#
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
    mitm) echo mitm.sh ;;
    wordlists) echo wordlists.sh ;;
    wsl) echo wsl.sh ;;
    *) return 1 ;;
  esac
}

section_ids() {
  local s
  for s in "${HAKPAK_SECTIONS[@]}"; do echo "${s%%:*}"; done
}

usage() {
  echo "Usage: setup.sh [section...] [--dry-run]"
  echo
  echo "With no sections, every section is installed. Sections:"
  local s
  for s in "${HAKPAK_SECTIONS[@]}"; do
    printf '  %-12s %s\n' "${s%%:*}" "${s#*:}"
  done
  echo
  echo "  --dry-run    print what would run, change nothing"
  echo "  -h, --help   show this help"
}

wanted=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) export HAKPAK_DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $arg"; echo; usage; exit 2 ;;
    *)
      if ! section_script "$arg" >/dev/null; then
        echo "unknown section: $arg"
        echo "valid sections: $(section_ids | paste -sd' ')"
        exit 2
      fi
      wanted+=("$arg")
      ;;
  esac
done

# Install order, whatever order the sections were named in; each runs once.
selected=()
while IFS= read -r id; do
  if [ "${#wanted[@]}" -eq 0 ] || _toolset_known "$id" "${wanted[@]}"; then
    selected+=("$id")
  fi
done < <(section_ids)

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

failed=()
for id in "${selected[@]}"; do
  echo "== Section: $id"
  bash "$HAKPAK_ROOT/install/$(section_script "$id")" || failed+=("$id")
done

echo
if [ "${#failed[@]}" -gt 0 ]; then
  log "Failed sections: ${failed[*]}"
  exit 1
fi
log_ok "Done: ${selected[*]}"
