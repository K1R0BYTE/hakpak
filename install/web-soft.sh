#!/usr/bin/env bash
# Web Tools section.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_normal_user

# Scanners
install_tool pipx sqlmap
install_tool pipx wafw00f
install_tool pipx arjun
install_tool apt whatweb

_install_nikto() {
  apt_install libnet-ssleay-perl libjson-perl &&
    _install_git nikto https://github.com/sullo/nikto &&
    run_step sudo ln -sf "$HAKPAK_OPT/nikto/program/nikto.pl" /usr/local/bin/nikto
}
install_tool custom nikto _install_nikto

_install_wpscan() {
  if has_command wpscan; then
    log_ok "wpscan already installed"
    return 0
  fi
  apt_install ruby-full ruby-dev build-essential libcurl4-openssl-dev zlib1g-dev &&
    run_step sudo gem install wpscan
}
install_tool custom wpscan _install_wpscan

# Probing and crawling
install_tool go httpx github.com/projectdiscovery/httpx/cmd/httpx@latest
install_tool go katana github.com/projectdiscovery/katana/cmd/katana@latest

# Directory fuzzing
install_tool go gobuster github.com/OJ/gobuster/v3@latest
install_tool go ffuf github.com/ffuf/ffuf/v2@latest
install_tool apt wfuzz

# Screenshots
install_tool go gowitness github.com/sensepost/gowitness@latest

install_summary
