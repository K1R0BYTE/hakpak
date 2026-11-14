#!/usr/bin/env bash
# Basic section: everyday tools, zsh and tmux, and their configs.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

install_section basic

link_shell_configs

install_summary
