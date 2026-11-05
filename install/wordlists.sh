#!/usr/bin/env bash
# Wordlists section.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

install_tool git seclists https://github.com/danielmiessler/SecLists "$HAKPAK_OPT/wordlists/seclists"

install_summary
