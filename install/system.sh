#!/usr/bin/env bash
# System section: base packages every other section relies on.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

log 'Updating package lists'
step 'package lists' sudo apt-get update

install_tool apt system-packages "build-essential net-tools bind9-dnsutils nfs-common cifs-utils"

install_summary
