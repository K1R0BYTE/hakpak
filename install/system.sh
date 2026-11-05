#!/usr/bin/env bash
# System section: base packages every other section relies on.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log 'Updating package lists'
step 'package lists' sudo apt-get update

install_tool apt system-packages "build-essential net-tools bind9-dnsutils isc-dhcp-server nfs-common cifs-utils"

log 'Giving your user ownership of /opt'
step "/opt ownership" sudo chown -R "${USER}:${USER}" "$HAKPAK_OPT"

install_summary
