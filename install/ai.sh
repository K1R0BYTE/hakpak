#!/usr/bin/env bash
# AI section: Claude Code with the skills from .claude/skills, the plugin
# marketplaces and the skill plugins, and Trail of Bits' Claude Code config.
# The dev section keeps the same rows. In a Docker Sandbox a read-only
# skills store is skipped and the plugins still install (see CONTEXT.md).
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# ai can be installed on its own, so it can't count on another section's refresh.
log 'Updating package lists'
step 'package lists' sudo apt-get update

install_section ai

claude_config_hint

install_summary
