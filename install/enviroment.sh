#!/usr/bin/env bash
# Environment section: Python, Jython and Go.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# Python: system pip stays untouched (PEP 668); tools go through pipx or a venv.
install_section environment
# Also for a pipx you already have: web, cloud, cicd and mitm install with it.
if tool_wanted pipx || has_command pipx; then
  step "pipx path" pipx ensurepath
fi

install_summary
