#!/usr/bin/env bash
# Network section: network tools and the clients for NFS and SMB shares.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

log 'Updating package lists'
step 'package lists' sudo apt-get update

install_section network

install_summary
