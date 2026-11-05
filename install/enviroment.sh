#!/usr/bin/env bash
# Environment section: Python, Jython and Go.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# Python: system pip stays untouched (PEP 668); tools go through pipx or a venv.
install_section environment
step "pipx path" pipx ensurepath

install_summary
