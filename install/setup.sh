#!/usr/bin/env bash
# hakpak setup: tick sections or single tools in a menu, or name sections
# as arguments.
#
#   setup.sh                         open the menu and tick what to install
#   setup.sh web pentest             only those sections (still in install order)
#   setup.sh all                     every section, in install order
#   setup.sh --dry-run [section...]  print what would run, change nothing
#
# Each section is one script in install/ (see CONTEXT.md). A failing section
# doesn't stop the next; setup lists the failed sections and exits non-zero.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# The script that installs each section.
section_script() {
  case "$1" in
    top) echo top.sh ;;
    dev) echo dev.sh ;;
    ai) echo ai.sh ;;
    network) echo network.sh ;;
    environment) echo enviroment.sh ;;
    basic) echo basic.sh ;;
    surfing) echo surfing.sh ;;
    web) echo web-soft.sh ;;
    pentest) echo pentest-soft.sh ;;
    cloud) echo cloud.sh ;;
    cicd) echo cicd.sh ;;
    mitm) echo mitm.sh ;;
    wordlists) echo wordlists.sh ;;
    wsl) echo wsl.sh ;;
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
  echo "  --dry-run    print what would run, change nothing"
  echo "  -h, --help   show this help"
}

unset HAKPAK_TOOLS
wanted=()
all=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) export HAKPAK_DRY_RUN=1 ;;
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

# The terminal's size as "rows cols": LINES and COLUMNS if set, else the
# terminal (when $1 is 1: stdout is one); 0 for an unknown or no limit.
menu_term_size() {
  local h="${LINES:-}" w="${COLUMNS:-}" size
  if { [ -z "$h" ] || [ -z "$w" ]; } && [ "$1" = 1 ]; then
    size="$(stty size 2>/dev/null < /dev/tty)" || size=""
    [ -z "$h" ] && h="${size% *}"
    [ -z "$w" ] && w="${size#* }"
  fi
  [[ "$h" =~ ^[0-9]+$ ]] || h=0
  [[ "$w" =~ ^[0-9]+$ ]] || w=0
  echo "$h $w"
}

# Wrap tool names (one per line on stdin) into lines indented under their
# section, each at most width-1 columns so it never reaches the last column.
wrap_tool_names() {
  local width="$1" indent="      " line="" name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -n "$line" ] && [ $((${#line} + 1 + ${#name})) -ge "$width" ]; then
      printf '%s\n' "$line"
      line=""
    fi
    if [ -z "$line" ]; then line="$indent$name"; else line="$line $name"; fi
  done
  [ -n "$line" ] && printf '%s\n' "$line"
  return 0
}

# Cut a line to at most width-1 columns, so it never reaches the last column.
_menu_fit() {
  local line="$1" width="$2"
  [ "${#line}" -ge "$width" ] && line="${line:0:width-1}"
  printf '%s' "$line"
}

# The menu: one checkbox per section and, in the open section, one per tool
# (from the Toolset manifest). Ticking a section ticks all its tools; a tool
# listed in several sections is one checkbox, ticked or unticked in all of
# them, and a section shows [x] (all its tools), [~] (some) or [ ] (none).
# The section under the cursor lists its tool names below it until it is
# opened; on a terminal too short for the whole list, the list is cut and an
# open section scrolls. Read key by key from stdin: j/k or up/down move,
# l or right opens a section, h or left closes it, space ticks, a ticks or
# unticks all, Enter installs, q quits. A section with no tools (wsl: only
# /etc/wsl.conf, ticked on WSL) has a checkbox of its own. Sets `wanted` to
# the ticked sections without tools and `picked` to the ticked tools;
# returns 1 if nothing is installed.
choose_sections() {
  local ids=() i k cur=0 ctool=-1 open=-1 wtop=0 key rest note="" lines=0
  local height cols width=80 all_rows section name tnote t
  mapfile -t ids < <(section_ids)
  local n=${#ids[@]} redraw=0
  local -a t_name=() t_note=() first=() count=() flag=() preview=() pcount=() out=()
  local -A on=()
  [ -t 1 ] && redraw=1
  read -r height cols < <(menu_term_size "$redraw")
  [ "${_HAKPAK_MENU_REDRAW:-0}" = 1 ] && redraw=1
  [ "$cols" -gt 0 ] && [ "$cols" -lt "$width" ] && width=$cols
  # One pass over the manifest; a problem with it is reported once.
  all_rows="$(toolset_rows "")" || all_rows=""
  for ((i = 0; i < n; i++)); do
    first[i]=${#t_name[@]}
    flag[i]=0
    # Not tab-separated for read: it would merge an empty source field.
    while IFS=$'\x1f' read -r section _ name _ tnote; do
      [ -n "$name" ] && [ "$section" = "${ids[i]}" ] || continue
      t_name+=("$name")
      t_note+=("$tnote")
      on[$name]=0
    done <<< "${all_rows//$'\t'/$'\x1f'}"
    count[i]=$((${#t_name[@]} - first[i]))
    if [ "${ids[i]}" = wsl ] && [ "${count[i]}" -eq 0 ]; then
      # Only /etc/wsl.conf, no tools; ticked on WSL.
      is_wsl && flag[i]=1
      t=/etc/wsl.conf
    else
      t="$(printf '%s\n' "${t_name[@]:first[i]:count[i]}")"
    fi
    preview[i]="$(printf '%s\n' "$t" | wrap_tool_names "$width")"
    pcount[i]=0
    [ -n "${preview[i]}" ] && pcount[i]=$(($(printf '%s\n' "${preview[i]}" | wc -l)))
  done
  # Room for tool lines below the sections; 0 rows known means no limit.
  local room=1000000 shown ticked_n box mark row
  [ "$height" -gt 0 ] && room=$((height - n - 4))
  while true; do
    out=("Arrows or j/k move, l/h open/close, space ticks, a all, Enter installs, q quits")
    for ((i = 0; i < n; i++)); do
      mark=" "
      [ "$i" = "$cur" ] && [ "$ctool" -lt 0 ] && mark=">"
      if [ "${count[i]}" -eq 0 ]; then
        box="[ ]"
        [ "${flag[i]}" = 1 ] && box="[x]"
        out+=("$mark $box ${ids[i]}")
      else
        ticked_n=0
        for ((k = first[i]; k < first[i] + count[i]; k++)); do
          [ "${on[${t_name[k]}]}" = 1 ] && ticked_n=$((ticked_n + 1))
        done
        box="[~]"
        [ "$ticked_n" -eq 0 ] && box="[ ]"
        [ "$ticked_n" -eq "${count[i]}" ] && box="[x]"
        printf -v row '%s %s %-12s %s' "$mark" "$box" "${ids[i]}" "$ticked_n/${count[i]}"
        out+=("$row")
      fi
      if [ "$i" = "$open" ]; then
        # The open section's tools, scrolled to keep the cursor in view.
        shown=${count[i]}
        [ "$shown" -gt "$room" ] && shown=$room
        [ "$shown" -lt 1 ] && shown=1
        [ "$ctool" -ge 0 ] && [ "$ctool" -lt "$wtop" ] && wtop=$ctool
        [ "$ctool" -ge $((wtop + shown)) ] && wtop=$((ctool - shown + 1))
        [ "$wtop" -gt $((count[i] - shown)) ] && wtop=$((count[i] - shown))
        for ((k = wtop; k < wtop + shown; k++)); do
          mark=" "
          [ "$k" = "$ctool" ] && mark=">"
          box="[ ]"
          [ "${on[${t_name[first[i] + k]}]}" = 1 ] && box="[x]"
          printf -v row '    %s %s %-24s %s' "$mark" "$box" "${t_name[first[i] + k]}" "${t_note[first[i] + k]}"
          row="${row%"${row##*[![:space:]]}"}"
          out+=("$(_menu_fit "$row" "$width")")
        done
      elif [ "$i" = "$cur" ] && [ -n "${preview[i]}" ] && [ "$room" -gt 0 ]; then
        # A list longer than the room left is cut, and says so.
        shown=${pcount[i]}
        if [ "$shown" -gt "$room" ]; then
          shown=$room
          [ "$shown" -gt 1 ] && mapfile -t -O "${#out[@]}" out < <(printf '%s\n' "${preview[i]}" | head -n $((shown - 1)))
          out+=("      ...")
        else
          mapfile -t -O "${#out[@]}" out <<< "${preview[i]}"
        fi
      fi
    done
    out+=("" "$note")
    note=""
    # On a terminal, draw over the last frame instead of below it.
    if [ "$lines" -gt 0 ] && [ "$redraw" = 1 ]; then
      printf '\033[%dA\033[J' "$lines"
    fi
    printf '%s\n' "${out[@]}"
    lines=${#out[@]}
    IFS= read -rsn1 key || { echo "Nothing installed"; return 1; }
    if [ "$key" = $'\033' ]; then
      IFS= read -rsn2 -t 1 rest || true
      case "$rest" in
        "[A" | OA) key=k ;;
        "[B" | OB) key=j ;;
        "[C" | OC) key=l ;;
        "[D" | OD) key=h ;;
        *) continue ;;
      esac
    fi
    case "$key" in
      j)
        if [ "$open" = "$cur" ] && [ "$ctool" -lt $((count[cur] - 1)) ]; then
          ctool=$((ctool + 1))
        elif [ "$cur" -lt $((n - 1)) ]; then
          cur=$((cur + 1)) ctool=-1 open=-1
        fi
        ;;
      k)
        if [ "$ctool" -ge 0 ]; then
          ctool=$((ctool - 1))
        elif [ "$cur" -gt 0 ]; then
          cur=$((cur - 1)) open=-1
        fi
        ;;
      l)
        if [ "${count[cur]}" -gt 0 ]; then
          [ "$open" = "$cur" ] || wtop=0
          open=$cur
          [ "$ctool" -lt 0 ] && ctool=0
        fi
        ;;
      h) open=-1 ctool=-1 ;;
      " ")
        if [ "$ctool" -ge 0 ]; then
          name="${t_name[first[cur] + ctool]}"
          on[$name]=$((1 - on[$name]))
        elif [ "${count[cur]}" -eq 0 ]; then
          flag[cur]=$((1 - flag[cur]))
        else
          local v=0
          for ((k = first[cur]; k < first[cur] + count[cur]; k++)); do
            [ "${on[${t_name[k]}]}" = 0 ] && v=1
          done
          for ((k = first[cur]; k < first[cur] + count[cur]; k++)); do
            on[${t_name[k]}]=$v
          done
        fi
        ;;
      a)
        local v=0
        for name in "${!on[@]}"; do [ "${on[$name]}" = 0 ] && v=1; done
        for ((i = 0; i < n; i++)); do
          [ "${count[i]}" -eq 0 ] && [ "${flag[i]}" = 0 ] && v=1
        done
        for name in "${!on[@]}"; do on[$name]=$v; done
        for ((i = 0; i < n; i++)); do flag[i]=$v; done
        ;;
      q) echo "Nothing installed"; return 1 ;;
      "")
        wanted=() picked=()
        for ((i = 0; i < n; i++)); do
          [ "${count[i]}" -eq 0 ] && [ "${flag[i]}" = 1 ] && wanted+=("${ids[i]}")
        done
        for name in "${t_name[@]}"; do
          [ "${on[$name]}" = 1 ] && ! _toolset_known "$name" "${picked[@]}" && picked+=("$name")
        done
        [ "$((${#wanted[@]} + ${#picked[@]}))" -gt 0 ] && return 0
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

# What to install: the tools ticked in the menu, or every tool of the named
# sections; a section with no tools in the manifest (wsl) is run as it is.
manifest_rows="$(toolset_rows "" 2>/dev/null)" || manifest_rows=""
picked=() chosen=()
if [ "${#wanted[@]}" -eq 0 ]; then
  choose_sections || exit 1
else
  chosen=("${wanted[@]}")
  named=("${wanted[@]}")
  wanted=()
  for id in "${named[@]}"; do
    if grep -q "^$id"$'\t' <<< "$manifest_rows"; then
      mapfile -t -O "${#picked[@]}" picked < <(awk -F'\t' -v s="$id" '$1 == s { print $3 }' <<< "$manifest_rows")
    else
      wanted+=("$id")
    fi
  done
fi

# The plan: each ticked tool is installed once, by one section (see
# toolset_plan). Sections with no tools are added in install order.
declare -A plan=() owner=()
if [ "${#picked[@]}" -gt 0 ]; then
  while IFS=$'\t' read -r id tools; do
    [ -n "$id" ] || continue
    plan[$id]="$tools"
    for t in $tools; do owner[$t]="$id"; done
  done < <(toolset_plan "${picked[@]}")
fi
# From the menu, the sections with a ticked tool count as chosen.
if [ "${#chosen[@]}" -eq 0 ]; then
  while IFS=$'\t' read -r section _ name _; do
    [ -n "${owner[$name]:-}" ] && ! _toolset_known "$section" "${chosen[@]}" && chosen+=("$section")
  done <<< "$manifest_rows"
fi
selected=()
while IFS= read -r id; do
  if [ -n "${plan[$id]+x}" ] || _toolset_known "$id" "${wanted[@]}"; then
    selected+=("$id")
    continue
  fi
  # A chosen section whose tools all come with others.
  _toolset_known "$id" "${chosen[@]}" || continue
  others=()
  while IFS=$'\t' read -r section _ name _; do
    [ "$section" = "$id" ] && [ -n "${owner[$name]:-}" ] || continue
    _toolset_known "${owner[$name]}" "${others[@]}" || others+=("${owner[$name]}")
  done <<< "$manifest_rows"
  if [ "${#others[@]}" -gt 0 ]; then
    log_ok "Section $id: its tools come with ${others[*]}"
  fi
done < <(section_ids)

failed=()
for id in "${selected[@]}"; do
  echo "== Section: $id"
  if [ -n "${plan[$id]+x}" ]; then
    HAKPAK_TOOLS="${plan[$id]}" bash "$HAKPAK_ROOT/install/$(section_script "$id")" || failed+=("$id")
  else
    bash "$HAKPAK_ROOT/install/$(section_script "$id")" || failed+=("$id")
  fi
done

echo
if [ "${#failed[@]}" -gt 0 ]; then
  log "Failed sections: ${failed[*]}"
  exit 1
fi
log_ok "Done: ${selected[*]}"

# With zsh just installed, hand the terminal over to it (see lib.sh).
if [ -n "${owner[zsh]:-}" ] || [ "${#picked[@]}" -eq 0 ]; then
  start_zsh_now "${selected[@]}"
fi
