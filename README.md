# What is it?

Predefined hacking toolset with configs (zsh, tmux, os)

For clean installed OS with saved top used commands history(.zsh_history)

Easy for edit and customize

To make comfortable hacking enviroment fast and efficient

# Requirements

```
Any apt-based distro: Debian 12+, Ubuntu 22.04+ or Kali
```

# How to Install?

```
sudo apt update && sudo apt -y upgrade && sudo apt -y install git

git clone https://github.com/K1R0BYTE/hakpak.git ${HOME}/.hakpak && cd ${HOME}/.hakpak/install

bash setup.sh
```

Run `setup.sh` as your normal user, not with sudo. Your user needs sudo rights; the scripts ask for your password only for the steps that need root (apt packages, `/usr/local`, `/etc`). Everything else installs as you: Go tools into `/opt/go`, pipx tools into `~/.local/bin`, and git tools into `/opt/<tool>`, owned by you.

After the install, log out and back in once: that picks up your new shell (zsh), the PATH for Go and pipx tools, and the wireshark group.

You can clone it anywhere; the scripts find the repo from their own path.

If a tool fails to install, the rest keep going and each section lists what failed at the end.

To see what a section would do without changing anything:

```
HAKPAK_DRY_RUN=1 bash web-soft.sh
```

# Toolset:

## System (apt)

* build-essential
* net-tools
* bind9-dnsutils
* nfs-common
* cifs-utils

## Basic (apt+configs)
* git
* vim
* wget
* curl
* fzf (Ctrl+R history search)
* zip
* unzip
* p7zip-full
* xclip
* zsh (oh-my-zsh, plugins, config)
* tmux (tpm, plugins, config)

## Surfing (apt)

* firefox-esr (Debian) / firefox (Ubuntu)
* torbrowser-launcher

## Environment (apt+go.dev)

### Python

* python3-pip
* python3-venv
* pipx
* python3-requests
* python3-setuptools

### Jython

* jython

### Golang

* latest Go from go.dev, in /usr/local/go

## Web Tools

* sqlmap (pipx)
* wafw00f (pipx)
* arjun (pipx)
* whatweb (apt)
* nikto (git)
* wpscan (gem)
* httpx (go)
* katana (go)
* gobuster (go)
* ffuf (go)
* wfuzz (apt)
* gowitness (go)

## Pentest Tools

* wireshark (apt)
* metasploit-framework (Rapid7 installer)
* exploitdb / searchsploit (git)
* hydra (apt)
* hashcat (apt)
* john (apt)
* nuclei (go)
* nmap (apt)
* masscan (apt)
* subdomainizer (git+venv)
* subfinder (go)
* amass (go)
* asnmap (go)
* linpeas (PEASS-ng release)

## MiTM

* hostapd (apt)
* dnsmasq-base (apt)
* iptables (apt)
* tcpdump (apt)
* mitmproxy (pipx)

## Wordlists (git)

* seclists (git)

## WSL (apt+configs)

* xfce4
* xrdp
* dbus-x11
* dnsmasq (DHCP server, config in `configs/dnsmasq.conf`)

# Tests

```
bats tests
shellcheck -x install/*.sh
```
