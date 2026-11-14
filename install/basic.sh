#!/usr/bin/env bash
# Basic section: everyday command line tools (git, curl, archivers).
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

install_section basic

install_summary
