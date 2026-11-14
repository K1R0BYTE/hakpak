# hakpak: hand an interactive bash over to zsh. Sourced from ~/.bashrc (the
# line is added by the basic and top sections).
#
# Changing the login shell is not enough where bash is started directly and
# the login shell is never read: a container or sandbox shell, a terminal
# set to run bash. Only an interactive bash on a terminal is handed over;
# scripts, `bash -c` and a `bash` you type from zsh stay bash.
# HAKPAK_NO_ZSH=1 switches it off.
case "$-" in
  *i*) ;;
  *) return 0 ;;
esac
[ -z "${HAKPAK_NO_ZSH:-}" ] || return 0
[ -z "${HAKPAK_ZSH_STARTED:-}" ] || return 0
if [ "${_HAKPAK_TTY:-0}" != 1 ]; then
  { [ -t 0 ] && [ -t 1 ]; } || return 0
fi
command -v zsh >/dev/null 2>&1 || return 0

# In a subshell first: if zsh can't start, this bash stays as it is. When it
# can, exec replaces bash, so SHELL and the marker are set only for zsh.
if "$(command -v zsh)" -c exit >/dev/null 2>&1; then
  if shopt -q login_shell; then
    HAKPAK_ZSH_STARTED=1 SHELL="$(command -v zsh)" exec zsh -l
  else
    HAKPAK_ZSH_STARTED=1 SHELL="$(command -v zsh)" exec zsh
  fi
fi
