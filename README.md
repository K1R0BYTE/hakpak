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

Re-running a section is safe. Your own dotfiles (`.zshrc`, `.tmux.conf`, `.dircolors`) are moved to `<file>.bak` once and replaced with links into `configs/`, so later runs change nothing. Configs under `/etc` (like `/etc/wsl.conf`) are copied, not linked, because root services read them. The curated `.zsh_history` is merged into your own history instead of linked, so Ctrl+R finds those commands and what you type stays local.

To see what a section would do without changing anything:

```
HAKPAK_DRY_RUN=1 bash web-soft.sh
```

# Toolset

Every tool is one row in [`install/toolset.txt`](install/toolset.txt): its section, how it installs (its kind), its name and where it comes from. Each section script installs its rows, and the list below is generated from the same file. To add or drop a tool, edit that file and run `tools/gen-readme`. Tools that need more than one step (`custom`) name a function in `install/custom.sh`.

<!-- toolset:start -->
## System

* build-essential (apt)
* net-tools (apt)
* bind9-dnsutils (apt)
* nfs-common (apt)
* cifs-utils (apt)

## Environment

* python3-pip (apt)
* python3-venv (apt)
* pipx (apt)
* python3-requests (apt)
* python3-setuptools (apt)
* jython (apt)
* go: latest Go from go.dev, in /usr/local/go

## Basic

* git (apt)
* vim (apt)
* wget (apt)
* curl (apt)
* fzf (apt): Ctrl+R history search
* zip (apt)
* unzip (apt)
* p7zip-full (apt)
* xclip (apt)
* zsh (apt): with the hakpak config and history
* oh-my-zsh: with zsh-syntax-highlighting and zsh-autosuggestions
* tmux (apt): with the hakpak config
* tpm (git)

## Surfing

* firefox: firefox-esr on Debian, firefox on Ubuntu
* torbrowser-launcher (apt): on Debian it's in contrib

## Web Tools

* sqlmap (pipx)
* wafw00f (pipx)
* arjun (pipx)
* whatweb (apt)
* nikto: git, linked into /usr/local/bin
* wpscan: gem, with its build dependencies
* httpx (go)
* katana (go)
* gobuster (go)
* ffuf (go)
* wfuzz (apt)
* gowitness (go)

## Pentest Tools

* wireshark: apt, with tcpdump; your user can capture
* metasploit: Rapid7 installer
* exploitdb: git, with searchsploit in /usr/local/bin
* hydra (apt)
* hashcat (apt)
* john (apt)
* nuclei: go, with the latest templates
* nmap (apt)
* masscan (apt)
* subdomainizer (venv): git clone with its own venv
* subfinder (go)
* amass (go)
* asnmap (go)
* linpeas (url): PEASS-ng release, in /opt/privesc

## MiTM

* hostapd (apt): Wi-Fi access point
* dnsmasq-base (apt): DHCP and DNS for AP clients, no system service
* iptables (apt): NAT and redirect rules
* tcpdump (apt)
* iw (apt): checks the Wi-Fi card can do AP mode
* mitmproxy (pipx)

## Wordlists

* seclists (git)

## WSL

* xfce4 (apt)
* xrdp (apt): remote desktop on port 3390
* dbus-x11 (apt)
<!-- toolset:end -->

# MiTM

Sample configs live in `configs/mitm/`:
- `hostapd.conf`: a WPA2 network called `hakpak`, password `hacktheplanet`. It uses 2.4 GHz 802.11n (20 MHz) on channel 6 so nearly any adapter and client works.
- `dnsmasq.conf`: DHCP and DNS for clients on 10.0.0.0/24.

No extra drivers are needed for hostapd: it talks to the kernel's standard Wi-Fi interface (nl80211). Your adapter's driver must support AP mode, and `setup-router --ap` checks that first. Adapters with in-kernel drivers that do: Atheros AR9271, Ralink RT3070/RT5370, MediaTek MT7610U/MT7612U. Most Realtek ones (RTL8812AU and others) need out-of-tree drivers. WSL has no Wi-Fi access, so run the AP on real Linux or a VM with the USB adapter passed through.

`setup-router` turns the machine into a router: it NATs clients on the in interface out through the out interface, turns on IP forwarding, and redirects chosen TCP ports to your proxy.

```
setup-router --ap                    # Wi-Fi AP on wlan0, internet via eth0, 80/443 -> localhost:8080
setup-router -i eth1 -o wlan0 -p 80  # wired clients on eth1, only HTTP redirected
setup-router -t 192.168.1.50:8080    # send traffic to Burp (invisible mode) on another machine
setup-router --no-redirect           # plain router, no interception
setup-router --down                  # remove everything it added
mitmproxy --mode transparent --showhost
```

Run it without `-i`/`-o` to pick the interfaces from a list. When 443 is redirected, QUIC (UDP 443) is blocked so browsers fall back to TCP through the proxy. If any step fails, setup-router undoes what it did. `setup-router --help` shows every option.

# WSL

`/etc/wsl.conf` turns on systemd and turns off Windows drive automount and interop. Run `wsl --shutdown` from Windows once after the install, then reopen WSL: xrdp then starts with systemd. `startrdp` and `stoprdp` start and stop it by hand.

# Tests

```
bats tests
shellcheck -x install/*.sh tools/setup-router tools/gen-readme
```

The tests fail if the README tool list doesn't match `install/toolset.txt`; `tools/gen-readme` updates it.
