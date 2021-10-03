#!/usr/bin/env bash

BLACK="\033[0;30m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[0;37m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "${RED}${1}${NOCOLOR}"
}
colorecho2() {
	echo -e "${GREEN}${1}${NOCOLOR}"
}
colorecho3() {
	echo -e "${PURPLE}${1}${NOCOLOR}"
}
colorecho '

██╗  ██╗ █████╗ ██╗  ██╗██████╗  █████╗ ██╗  ██╗
██║  ██║██╔══██╗██║ ██╔╝██╔══██╗██╔══██╗██║ ██╔╝
███████║███████║█████╔╝ ██████╔╝███████║█████╔╝ 
██╔══██║██╔══██║██╔═██╗ ██╔═══╝ ██╔══██║██╔═██╗ 
██║  ██║██║  ██║██║  ██╗██║     ██║  ██║██║  ██╗
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝
                                                
'
colorecho2 'Welcome to HAKPAK Setup'
colorecho2 'There are two options to install'
colorecho2 'Auto Mode - just installs everything'
colorecho2 'Manual Mode - you can choose which packages to install\n'

colorecho3 'Please select installation mode, choose 1 or 2 !\n'
	choices=("Auto" "Manual")
	select choice in "${choices[@]}"; do
		case $choice in
		Auto)

        # System
        bash system.sh
        # Enviroment
        bash enviroment.sh
        # Basic
        bash basic.sh
        # Security Soft
        bash web-soft.sh
        bash pentest-soft.sh
        # Wordlists
        bash wordlists.sh
        # WSL
        bash wsl.sh
        break
        ;;

        Manual)
		
        echo -e "${Red}Edit setup.sh to comment out unnecessary *.sh scripts or tools in scripts itself))"
		break
        ;;
		esac
    done
