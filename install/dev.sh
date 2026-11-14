#!/usr/bin/env bash
# Dev section: a developer environment. Search and shell tools (ripgrep, fd,
# jq, delta, gh, shellcheck, shfmt), the Python, Node, Go and Rust
# toolchains, Claude Code with plugin marketplaces and plugins, and the
# shell and git configs that go with them. Based on the Trail of Bits
# devcontainer, without the container: nothing here builds or runs one.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# dev can be installed on its own, so it can't count on another section's refresh.
log 'Updating package lists'
step 'package lists' sudo apt-get update

install_section dev

link_dev_configs

dev_hint

install_summary
