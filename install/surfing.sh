#!/usr/bin/env bash
# Surfing section: web browsers.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Debian ships firefox-esr; Ubuntu ships firefox.
_install_firefox() {
  if apt-cache show firefox-esr >/dev/null 2>&1; then
    apt_install firefox-esr
  else
    apt_install firefox
  fi
}
install_tool custom firefox _install_firefox

# On Debian it lives in contrib, which may not be enabled.
install_tool apt torbrowser-launcher

install_summary
