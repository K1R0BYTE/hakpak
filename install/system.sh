#!/usr/bin/env bash

RED="\033[1;31m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "[*] ${RED}${1}${NOCOLOR}"
}

colorecho 'Starting Updating Repositories'

sudo apt update

colorecho 'Finished Updating Repositories'

colorecho 'Starting Installing System Soft'

sudo apt -y install build-essential net-tools dnsutils isc-dhcp-server nfs-common cifs-utils apt-transport-https

colorecho 'Finished Installing System Soft'

colorecho 'Starting Installing Basic Soft'

sudo apt -y install git vim wget curl peco firefox-esr zip unzip p7zip-full guake torbrowser-launcher

colorecho 'Finished Installing Basic Soft'

colorecho 'Starting Configuring System'

sudo chown -R ${USER}:${USER} /opt

colorecho 'Finished Configuring System'
