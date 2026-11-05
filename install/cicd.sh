#!/usr/bin/env bash
# CI/CD section.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

install_section cicd

install_summary
