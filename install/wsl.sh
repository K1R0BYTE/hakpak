#!/usr/bin/env bash
# WSL section: WSL config, DHCP server config and the xrdp remote desktop.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# Configs (linking is reworked in issue #2)
log 'Configuring WSL'
step 'wsl.conf' sudo ln -sv "${HAKPAK_ROOT}/configs/wsl.conf" /etc/wsl.conf

# DHCP server: dnsmasq in DHCP-only mode (configs/dnsmasq.conf). The config
# is copied, not linked, so a root service never reads a file your user can edit.
install_tool apt dnsmasq
step 'dnsmasq.conf' sudo install -m 644 "${HAKPAK_ROOT}/configs/dnsmasq.conf" /etc/dnsmasq.d/hakpak.conf
step 'dnsmasq.conf' sudo systemctl restart dnsmasq

# Remote GUI
install_tool apt remote-desktop "xfce4 xrdp dbus-x11"

log 'Configuring xrdp on port 3390'
# xrdp needs to read the TLS key in /etc/ssl/private
step 'xrdp config' sudo adduser xrdp ssl-cert
step 'xrdp config' sudo cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.bak
step 'xrdp config' sudo sed -i 's/3389/3390/g' /etc/xrdp/xrdp.ini
step 'xrdp config' sudo sed -i 's/max_bpp=32/#max_bpp=32\nmax_bpp=128/g' /etc/xrdp/xrdp.ini
step 'xrdp config' sudo sed -i 's/xserverbpp=24/#xserverbpp=24\nxserverbpp=128/g' /etc/xrdp/xrdp.ini
step 'xrdp config' sh -c 'echo xfce4-session > ~/.xsession'

step 'services' sudo systemctl enable dbus
step 'services' sudo /etc/init.d/dbus start
step 'services' sudo /etc/init.d/xrdp start

install_summary
