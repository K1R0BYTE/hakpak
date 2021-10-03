#!/usr/bin/env bash

RED="\033[1;31m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "[*] ${RED}${1}${NOCOLOR}"
}

colorecho 'Starting Installing Wordlists'

# SecLists
wget -c https://github.com/danielmiessler/SecLists/archive/master.zip -O /tmp/SecLists.zip
unzip /tmp/SecLists.zip -d /opt/wordlists/seclists
rm -f /tmp/SecLists.zip

# Fuzz
wget -c https://raw.githubusercontent.com/Bo0oM/fuzz.txt/master/fuzz.txt -O /opt/wordlists/fuzz.txt

colorecho 'Finished Installing Wordlists'
