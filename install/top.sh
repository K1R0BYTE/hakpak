#!/usr/bin/env bash
# Top section: the tools used most. vim, fzf, zsh with oh-my-zsh, tmux and
# their configs (the same ones the basic section installs, so top works on
# its own), and the Claude Code CLI with the skills from .claude/skills.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# top is the first section, so it can't count on network's refresh.
log 'Updating package lists'
step 'package lists' sudo apt-get update

install_section top

link_shell_configs

install_summary
