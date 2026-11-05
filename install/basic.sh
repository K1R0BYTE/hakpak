#!/usr/bin/env bash
# Basic section: everyday tools, zsh and tmux.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_tool apt basic-packages "git vim wget curl zip unzip p7zip-full xclip fzf torbrowser-launcher"

# Debian ships firefox-esr; Ubuntu ships firefox.
_install_firefox() {
  if apt-cache show firefox-esr >/dev/null 2>&1; then
    apt_install firefox-esr
  else
    apt_install firefox
  fi
}
install_tool custom firefox _install_firefox

# ZSH
ZSH="${HOME}/.oh-my-zsh"
ZSH_CUSTOM="$ZSH/custom"

install_tool apt zsh

_install_oh_my_zsh() {
  if [ -d "$ZSH" ]; then
    log_ok "oh-my-zsh already installed"
    return 0
  fi
  local installer
  installer="${TMPDIR:-/tmp}/hakpak-ohmyzsh.$$.sh"
  run_step curl -fsSL -o "$installer" https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh &&
    run_step sh "$installer" --unattended &&
    run_step sudo chsh -s "$(command -v zsh || echo /usr/bin/zsh)" "$USER" &&
    run_step rm -f "$installer"
}
install_tool custom oh-my-zsh _install_oh_my_zsh
install_tool git zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
install_tool git zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

# Configs (linking is reworked in issue #2)
run_step mv "${HOME}/.zshrc" "${HOME}/.zshrc.bak"
run_step ln -sv "${HAKPAK_ROOT}/configs/zsh/.zshrc" "${HOME}/.zshrc"

run_step mv "${HOME}/.zsh_history" "${HOME}/.zsh_history.bak"
run_step ln -sv "${HAKPAK_ROOT}/configs/zsh/.zsh_history" "${HOME}/.zsh_history"

run_step mv "${HOME}/.dircolors" "${HOME}/.dircolors.bak"
run_step ln -sv "${HAKPAK_ROOT}/configs/.dircolors" "${HOME}/.dircolors"

# Tmux
install_tool apt tmux
run_step rm -rf "${HOME}"/.tmux*
install_tool git tpm https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm"
run_step ln -sv "${HAKPAK_ROOT}/configs/tmux/.tmux.conf" "${HOME}/.tmux.conf"
run_step tmux source-file "${HOME}/.tmux.conf"

install_summary
