#!/usr/bin/env bash
# WSL section: only /etc/wsl.conf, from configs/wsl.conf. The menu ticks it
# by default on WSL; outside WSL it does nothing.
#
# No /etc/wsl.conf yet: hakpak's is copied in. The same file: left alone.
# A different one: the difference is shown and you pick which to keep
# (k or h, Enter takes the recommendation). Without a terminal yours is
# kept; HAKPAK_WSL_CONF=keep or replace decides without asking. Replacing
# backs yours up to /etc/wsl.conf.bak (see link_config).
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

target="$HAKPAK_SYSROOT/etc/wsl.conf"
ours="$HAKPAK_ROOT/configs/wsl.conf"

case "${HAKPAK_WSL_CONF:-}" in
  "" | keep | replace) ;;
  *) echo "HAKPAK_WSL_CONF must be keep or replace, not: $HAKPAK_WSL_CONF"; exit 2 ;;
esac

if ! is_wsl; then
  log_ok "Not WSL: /etc/wsl.conf left alone"
  exit 0
fi

if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$ours" "$target"; then
  log_ok "/etc/wsl.conf already up to date"
  exit 0
fi

# Ask which wsl.conf to keep; prints keep or replace. $1 is the
# recommendation, taken on Enter. End of input keeps yours.
choose_wsl_conf() {
  local rec="$1" def=k ans
  [ "$rec" = replace ] && def=h
  while true; do
    printf "Keep yours (k) or use hakpak's (h)? [%s] " "$def" >&2
    if ! IFS= read -r ans; then
      echo >&2
      echo keep
      return
    fi
    [ -n "$ans" ] || ans="$def"
    case "$ans" in
      k | K) echo keep; return ;;
      h | H) echo replace; return ;;
    esac
  done
}

if [ -e "$target" ] && [ ! -L "$target" ]; then
  echo "Your /etc/wsl.conf differs from hakpak's:"
  diff -u --label "/etc/wsl.conf (yours)" --label "configs/wsl.conf (hakpak)" "$target" "$ours"
  echo "hakpak's turns on systemd (xrdp in the rdp section starts with it) and"
  echo "turns off Windows drive automount (/mnt/c) and interop (running .exe files)."
  if grep -qiE '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$target" 2>/dev/null; then
    rec=keep
    echo "Recommended: keep yours (it already turns on systemd)"
  else
    rec=replace
    echo "Recommended: use hakpak's (yours doesn't turn on systemd)"
  fi
  choice="${HAKPAK_WSL_CONF:-}"
  if [ -z "$choice" ]; then
    if [ -t 0 ] || [ "${_HAKPAK_PROMPT_TTY:-0}" = 1 ]; then
      choice="$(choose_wsl_conf "$rec")"
    else
      choice=keep
    fi
  fi
  if [ "$choice" = keep ]; then
    log_ok "Kept your /etc/wsl.conf. To use hakpak's: HAKPAK_WSL_CONF=replace setup.sh wsl"
    exit 0
  fi
fi

# Copied, not linked: WSL reads it as root at boot.
step 'wsl.conf' link_config wsl.conf /etc/wsl.conf &&
  log 'Run "wsl --shutdown" from Windows and reopen WSL to apply /etc/wsl.conf'
install_summary
