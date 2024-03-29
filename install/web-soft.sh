#!/usr/bin/env bash

RED="\033[1;31m"
NOCOLOR="\033[0m"

colorecho() {
	echo -e "[*] ${RED}${1}${NOCOLOR}"
}

colorecho 'Starting Installing Web Soft'

# Go Variables
export GO111MODULE=on
export GOPATH="/opt/go"
export PATH=$PATH:$(go env GOPATH)/bin

# Web
## Sqlmap
sudo apt -y install sqlmap
## CMSeeK
sudo apt -y install cmseek
## Nikto
sudo apt -y install nikto
## Wpscan
sudo apt -y install wpscan
## wafw00f
sudo apt -y install wafw00f
## Whatweb
sudo apt -y install whatweb
## Arjun
sudo apt -y install arjun
## Httprobe
go get -u github.com/tomnomnom/httprobe
## Hakrawler
go get -u github.com/hakluke/hakrawler
## Gospider
go get -u github.com/jaeles-project/gospider
## BurSsuite Community
sudo apt -y install burpsuite
## BurpSuite Pro
wget -c https://portswigger.net/burp/releases/download?product=pro&version=2021.8.4&type=Linux -O /tmp/burppro.sh
bash /tmp/burppro.sh -q -dir /opt/burpsuitepro
rm -f /tmp/burppro.sh

# Directory fuzzing
## Gobuster
sudo apt -y install gobuster
## Wfuzz
sudo apt -y install wfuzz
## Ffuf
sudo apt -y install ffuf

# Screenshooting
## EyeWitness
sudo apt -y install eyewitness

colorecho 'Finished Installing Web Soft'