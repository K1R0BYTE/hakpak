#!/usr/bin/env bash
# Basic section: everyday tools, zsh and tmux, and their configs.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

install_section basic

# Configs: your own files are backed up once, re-runs change nothing.
step .zshrc link_config zsh/.zshrc "${HOME}/.zshrc"
step .dircolors link_config .dircolors "${HOME}/.dircolors"
# History is merged, not linked, so new commands stay out of the repo.
step .zsh_history merge_history zsh/.zsh_history "${HOME}/.zsh_history"

step .tmux.conf link_config tmux/.tmux.conf "${HOME}/.tmux.conf"
# Reload only if a tmux server is running.
if tmux info >/dev/null 2>&1; then
  step 'tmux reload' tmux source-file "${HOME}/.tmux.conf"
fi

install_summary
