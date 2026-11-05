#!/usr/bin/env bash
# Basic section: everyday tools, zsh and tmux.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_tool apt basic-packages "git vim wget curl zip unzip p7zip-full xclip fzf"

# ZSH
ZSH="${HOME}/.oh-my-zsh"
ZSH_CUSTOM="$ZSH/custom"

install_tool apt zsh

_install_oh_my_zsh() {
  if [ -f "$ZSH/oh-my-zsh.sh" ]; then
    log_ok "oh-my-zsh already installed"
    return 0
  fi
  run_step git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH" &&
    run_step sudo chsh -s "$(command -v zsh || echo /usr/bin/zsh)" "$USER"
}
# Plugins go inside oh-my-zsh, so only clone them once it's there.
if install_tool custom oh-my-zsh _install_oh_my_zsh; then
  install_tool git zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  install_tool git zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# Configs (full rework in issue #2). Back up a real file only, never
# an earlier hakpak link, so re-runs don't overwrite the backup.
_link_home_config() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return 0
  fi
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    run_step mv "$dest" "$dest.bak" || return 1
  fi
  run_step ln -sfnv "$src" "$dest"
}
step .zshrc _link_home_config "${HAKPAK_ROOT}/configs/zsh/.zshrc" "${HOME}/.zshrc"
step .zsh_history _link_home_config "${HAKPAK_ROOT}/configs/zsh/.zsh_history" "${HOME}/.zsh_history"
step .dircolors _link_home_config "${HAKPAK_ROOT}/configs/.dircolors" "${HOME}/.dircolors"

# Tmux
install_tool apt tmux
install_tool git tpm https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm"
step .tmux.conf _link_home_config "${HAKPAK_ROOT}/configs/tmux/.tmux.conf" "${HOME}/.tmux.conf"
# Reload only if a tmux server is running.
if tmux info >/dev/null 2>&1; then
  step 'tmux reload' tmux source-file "${HOME}/.tmux.conf"
fi

install_summary
