#!/usr/bin/env bash
# RDP section: the xrdp remote desktop. On WSL it needs systemd, which the
# wsl section turns on.
# Tools are listed in install/toolset.txt.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# xrdp starts with systemd, which /etc/wsl.conf turns on: that is the wsl
# section's job.
if is_wsl && ! grep -qs '^systemd=true' "$HAKPAK_SYSROOT/etc/wsl.conf"; then
  log 'systemd is off in /etc/wsl.conf: install the wsl section too, so xrdp starts at boot'
fi

# DNS and DHCP are left to WSL itself.

# Remote GUI
install_section rdp

log 'Configuring xrdp on port 3390'
# xrdp needs to read the TLS key in /etc/ssl/private
step 'xrdp config' sudo adduser xrdp ssl-cert
# Back up the stock config once; the edits are anchored so re-runs are no-ops.
if [ ! -e /etc/xrdp/xrdp.ini.bak ]; then
  step 'xrdp config' sudo cp -p /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.bak
fi
step 'xrdp config' sudo sed -i -E 's/^port=3389$/port=3390/; s/^max_bpp=32$/max_bpp=128/; s/^#?xserverbpp=24$/xserverbpp=128/' /etc/xrdp/xrdp.ini
step 'xrdp config' sh -c 'echo xfce4-session > ~/.xsession'

# Start xrdp at boot with systemd. Until WSL restarts with systemd on,
# start it now only if systemd is already running.
step 'services' sudo systemctl enable xrdp
if [ -d /run/systemd/system ]; then
  step 'services' sudo systemctl restart xrdp
else
  log 'Run "wsl --shutdown" from Windows and reopen WSL to start xrdp with systemd'
fi

install_summary
