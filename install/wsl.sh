#!/usr/bin/env bash

RED="\033[1;31m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "[*] ${RED}${1}${NOCOLOR}"
}

colorecho 'Starting Configuring WSL System'

sudo ln -sv ${HOME}/.hakpak/configs/wsl.conf /etc/wsl.conf
sudo mv /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
sudo ln -sv ${HOME}/.hakpak/configs/dhcpd.conf /etc/dhcp/dhcpd.conf

colorecho 'Finished Configuring WSL System'

colorecho 'Starting Installing Remote GUI'

sudo apt -y install xfce4 xrdp
sudo cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.bak
sudo sed -i 's/3389/3390/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/max_bpp=32/#max_bpp=32\nmax_bpp=128/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/xserverbpp=24/#xserverbpp=24\nxserverbpp=128/g' /etc/xrdp/xrdp.ini

echo xfce4-session > ~/.xsession

sudo systemctl enable dbus
sudo /etc/init.d/dbus start
sudo /etc/init.d/xrdp start

sudo /etc/init.d/xrdp status

colorecho 'Finished Installing Remote GUI'