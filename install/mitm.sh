#!/usr/bin/env bash
# MiTM section: rogue access point and traffic interception.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

install_section mitm

install_summary
