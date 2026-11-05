#!/usr/bin/env bash
# System section: base packages every other section relies on.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

log 'Updating package lists'
step 'package lists' sudo apt-get update

install_section system

install_summary
