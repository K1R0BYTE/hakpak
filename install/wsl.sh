#!/usr/bin/env bash
# WSL section: WSL config, DHCP server config and the xrdp remote desktop.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Configs (linking is reworked in issue #2)
log 'Configuring WSL'
run_step sudo ln -sv "${HAKPAK_ROOT}/configs/wsl.conf" /etc/wsl.conf
run_step sudo mv /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
run_step sudo ln -sv "${HAKPAK_ROOT}/configs/dhcpd.conf" /etc/dhcp/dhcpd.conf

# Remote GUI
install_tool apt remote-desktop "xfce4 xrdp dbus-x11"

log 'Configuring xrdp on port 3390'
run_step sudo cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.bak
run_step sudo sed -i 's/3389/3390/g' /etc/xrdp/xrdp.ini
run_step sudo sed -i 's/max_bpp=32/#max_bpp=32\nmax_bpp=128/g' /etc/xrdp/xrdp.ini
run_step sudo sed -i 's/xserverbpp=24/#xserverbpp=24\nxserverbpp=128/g' /etc/xrdp/xrdp.ini
run_step sh -c 'echo xfce4-session > ~/.xsession'

run_step sudo systemctl enable dbus
run_step sudo /etc/init.d/dbus start
run_step sudo /etc/init.d/xrdp start

install_summary
