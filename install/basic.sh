#!/usr/bin/env bash
# Basic section: everyday tools, zsh and tmux.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

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

# Configs: your own files are backed up once, re-runs change nothing.
step .zshrc link_config zsh/.zshrc "${HOME}/.zshrc"
step .dircolors link_config .dircolors "${HOME}/.dircolors"
# History is merged, not linked, so new commands stay out of the repo.
step .zsh_history merge_history zsh/.zsh_history "${HOME}/.zsh_history"

# Tmux
install_tool apt tmux
install_tool git tpm https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm"
step .tmux.conf link_config tmux/.tmux.conf "${HOME}/.tmux.conf"
# Reload only if a tmux server is running.
if tmux info >/dev/null 2>&1; then
  step 'tmux reload' tmux source-file "${HOME}/.tmux.conf"
fi

install_summary
