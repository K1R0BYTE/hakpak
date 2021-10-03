# What is it ?

Predefined hacking toolset with configs(zsh, tmux, burp, os)

For clean installed OS with saved top used commands history(.zsh_history)

Easy for edit and customize

To make comfortable hacking enviroment fast and efficient

# Requirements

```
Kali linux: no prerequisites

Other linux distro: add Kali repositories (setup/addrep.sh)

```

# How to Install?

```
sudo apt update && sudo apt -y upgrade  && sudo apt -y install git 

git clone https://github.com/K1R0BYTE/hakpak.git ${HOME}/.hakpak && cd ${HOME}/.hakpak/install

bash setup.sh
```

# Toolset:

## System (apt)

* build-essential 
* net-tools
* dnsutils
* isc-dhcp-server
* nfs-common
* cifs-utils
* apt-transport-https

## Basic (apt+configs)
* vim
* wget
* curl
* peco
* firefox-esr
* torbrowser-launcher
* zip
* unzip
* p7zip-full
* guake
* zsh (plugins, config)
* tmux (plugins, config)

## Enviroment (apt+pip)

### Python

* python3-pip
* virtualenv

### Python libs

* requests 
* setuptools

## Web Tools (apt+git+direct)

* sqlmap
* cmseek
* nikto
* wpscan
* wafw00f
* whatweb
* arjun
* httprobe (git)
* hakrawler (git)
* gospider (git)
* gobuster
* wfuzz
* ffuf
* eyewitness
* burpsuite-community
* burpsuite-pro-2021.8.3 (direct)

## Pentest Tools (apt+git)

* wireshark
* tcpdump
* metasploit-framework
* exploitdb
* hydra
* hashcat
* john
* nuclei
* nmap
* masscan
* dnmasscan
* gospider (git)
* subdomainizer (git)
* subscraper (git)
* subfinder (git)
* asnlookup (git)
* metabigor (git)
* domlink (git)
* amass
* interlace (git)
* linpeas (git)

## Wordlists (git)

* seclists (git)
* fuzz-b00m (git)

## WSL (apt+configs)

* xfce4
* xrdp