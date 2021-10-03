#!/usr/bin/env bash

RED="\033[1;31m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "[*] ${RED}${1}${NOCOLOR}"
}

colorecho 'Starting Installing Python Soft'

# Python3 (pip + virtualenv)
sudo apt -y install python3-pip
sudo python3 -m pip install --upgrade pip
sudo apt -y install virtualenv
# Python3 libs
sudo python3 -m pip install requests setuptools

colorecho 'Finished Installing Python Soft'

colorecho 'Starting Installing Jython Soft'

sudo apt -y install jython

colorecho 'Finished Installing Jython Soft'

colorecho 'Starting Installing GoLang Soft'

sudo apt install golang -y

colorecho 'Finished Installing GoLang Soft'
