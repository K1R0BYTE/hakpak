#!/usr/bin/env bash
# WSL section: only /etc/wsl.conf, from configs/wsl.conf. The menu ticks it
# by default on WSL; outside WSL it does nothing. It runs just before rdp,
# whose xrdp needs the systemd this config turns on.
#
# No /etc/wsl.conf yet: hakpak's is copied in. The same file: left alone.
# A different one (or a link to one): the difference is shown with a
# recommendation and you pick which to keep (k or h, Enter takes the
# recommendation). Without a terminal yours is kept; HAKPAK_WSL_CONF=keep or
# replace decides without asking. Replacing backs yours up to
# /etc/wsl.conf.bak (or a timestamped .bak.*).
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

target="$HAKPAK_SYSROOT/etc/wsl.conf"
ours="$HAKPAK_ROOT/configs/wsl.conf"

if ! is_wsl; then
  log_ok "Not WSL: /etc/wsl.conf left alone"
  exit 0
fi

case "${HAKPAK_WSL_CONF:-}" in
  "" | keep | replace) ;;
  *) echo "HAKPAK_WSL_CONF must be keep or replace, not: $HAKPAK_WSL_CONF"; exit 2 ;;
esac

if config_up_to_date "$ours" "$target"; then
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

# A link that an older hakpak made into the repo is just replaced by a copy.
mine=0
if [ -L "$target" ]; then
  case "$(readlink -f "$target")" in
    "$HAKPAK_ROOT"/*) ;;
    *) mine=1 ;;
  esac
elif [ -e "$target" ]; then
  mine=1
fi

if [ "$mine" = 1 ]; then
  if [ ! -f "$target" ]; then
    echo "/etc/wsl.conf is not a file: move it away, then run the wsl section again"
    exit 1
  fi
  echo "Your /etc/wsl.conf differs from hakpak's:"
  diff -u --label "/etc/wsl.conf (yours)" --label "configs/wsl.conf (hakpak)" "$target" "$ours"
  echo "hakpak's turns on systemd (xrdp in the rdp section starts with it) and"
  echo "turns off Windows drive automount (/mnt/c) and interop (running .exe files)."
  if wsl_conf_has_systemd "$target"; then
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
  # link_config backs up a file but drops a link, so keep what a link of
  # yours points to as a real file first.
  if [ -L "$target" ]; then
    _run_at "$target" cp -L "$target" "$(_backup_path "$target")" ||
      { echo "failed: wsl.conf backup"; exit 1; }
  fi
fi

# Copied, not linked: WSL reads it as root at boot.
step 'wsl.conf' link_config wsl.conf /etc/wsl.conf || exit 1
log_ok "/etc/wsl.conf installed"
log 'Run "wsl --shutdown" from Windows and reopen WSL to apply it'
