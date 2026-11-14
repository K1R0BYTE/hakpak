# hakpak: hand an interactive bash over to zsh. Sourced from ~/.bashrc (the
# line is added by the basic and top sections).
#
# Changing the login shell is not enough where bash is started directly and
# the login shell is never read: a container or sandbox shell, a terminal
# set to run bash. Only an interactive bash at a terminal is handed over.
# Scripts, `bash -c` (also `bash -ic`) and a `bash` you start from zsh stay
# bash. HAKPAK_NO_ZSH=1 switches it off.
case "$-" in
  *c*) return 0 ;;
  *i*) ;;
  *) return 0 ;;
esac
[ -z "${HAKPAK_NO_ZSH:-}" ] || return 0
# Set for the zsh started here or by setup.sh, and so for a bash under it.
[ -z "${HAKPAK_ZSH_STARTED:-}" ] || return 0
if [ "${_HAKPAK_TTY:-0}" != 1 ]; then
  { [ -t 0 ] && [ -t 1 ]; } || return 0
fi
# A bash started from zsh (your login shell, say) is one you asked for.
case "$(cat "/proc/$PPID/comm" 2>/dev/null)" in
  zsh | -zsh) return 0 ;;
esac
_hakpak_zsh="$(command -v zsh 2>/dev/null)" || { unset _hakpak_zsh; return 0; }

# Try zsh first: a zsh that can't run (a broken install) must not cost you
# your bash. Then exec replaces bash, so SHELL and the marker are set only
# for zsh.
if "$_hakpak_zsh" -c exit >/dev/null 2>&1; then
  if shopt -q login_shell; then
    HAKPAK_ZSH_STARTED=1 SHELL="$_hakpak_zsh" exec "$_hakpak_zsh" -l
  else
    HAKPAK_ZSH_STARTED=1 SHELL="$_hakpak_zsh" exec "$_hakpak_zsh"
  fi
fi
unset _hakpak_zsh
