#!/usr/bin/env bash

RED="\033[1;31m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "[*] ${RED}${1}${NOCOLOR}"
}
colorecho2() {
	echo -e "${PURPLE}${1}${NOCOLOR}"
}

colorecho2 '!!! WARNING !!!\nUpdating packages on non kali distro can break OS! Are you sure to continue?\n'
	choices=("Yes" "No")
	select choice in "${choices[@]}"; do
		case $choice in
		Yes)

		colorecho 'Starting Updating Repositories'

		sudo sh -c "echo 'deb https://http.kali.org/kali kali-rolling main non-free contrib' > /etc/apt/sources.list.d/kali.list"
		sudo apt -y install gnupg
		wget 'https://archive.kali.org/archive-key.asc'
		sudo apt-key add archive-key.asc
		rm -f archive-key.asc
		sudo sh -c "echo 'Package: *'>/etc/apt/preferences.d/kali.pref; echo 'Pin: release a=kali-rolling'>>/etc/apt/preferences.d/kali.pref; echo 'Pin-Priority: 50'>>/etc/apt/preferences.d/kali.pref"
		sudo apt update

		colorecho 'Finished Updating Repositories'

        break
        ;;

        No)
		
        echo -e "${Red}Now you can switch to Kali distro or search how to add kali repository to your current linux distro safely"
		break
        ;;
		esac
    done

