#!/usr/bin/env bash
# Install steps for the `custom` tools in install/toolset.txt: tools whose
# install is more than one install_tool kind. Sourced by lib.sh, so the
# manifest check can see every function. Each one runs its commands through
# run_step (directly or via the _install_<kind> helpers) so dry run works.

# --- Environment ---

# Go from go.dev: distro packages are too old for current Go tools.
_go_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv6l|armv7l) echo armv6l ;;
    i386|i686) echo 386 ;;
    *) return 1 ;;
  esac
}

_install_go_toolchain() {
  local version arch tarball
  arch="$(_go_arch)" || { echo "unsupported CPU: $(uname -m)"; return 1; }
  if [ "${HAKPAK_DRY_RUN:-0}" = "1" ]; then
    version="${HAKPAK_GO_VERSION:-go1.x}"
  else
    version="${HAKPAK_GO_VERSION:-$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)}"
  fi
  [ -n "$version" ] || { echo "could not find the latest Go version"; return 1; }
  if [ -x /usr/local/go/bin/go ] && [ "$(/usr/local/go/bin/go env GOVERSION)" = "$version" ]; then
    log_ok "Go $version already installed"
    return 0
  fi
  # Download and unpack in a private temp dir first; only replace
  # /usr/local/go once the new tree is complete.
  local tmp rc
  tmp="$(make_temp_dir)" || return 1
  tarball="$tmp/${version}.linux-${arch}.tar.gz"
  run_step curl -fsSL -o "$tarball" "https://go.dev/dl/${version}.linux-${arch}.tar.gz" &&
    run_step tar -C "$tmp" -xzf "$tarball" &&
    run_step sudo rm -rf /usr/local/go &&
    run_step sudo mv "$tmp/go" /usr/local/go &&
    run_step sudo chown -R root:root /usr/local/go
  rc=$?
  run_step rm -rf "$tmp"
  return $rc
}

# --- Basic ---

# Plugins go inside oh-my-zsh, so they're cloned only once it's there.
_install_oh_my_zsh() {
  local zsh_dir="${HOME}/.oh-my-zsh"
  local plugins="$zsh_dir/custom/plugins"
  if [ -f "$zsh_dir/oh-my-zsh.sh" ]; then
    log_ok "oh-my-zsh already installed"
  else
    run_step git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$zsh_dir" &&
      run_step sudo chsh -s "$(command -v zsh || echo /usr/bin/zsh)" "$USER" ||
      return 1
  fi
  # Each plugin is its own tool, so a failed clone is reported by its name.
  install_tool git zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins/zsh-syntax-highlighting"
  install_tool git zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions "$plugins/zsh-autosuggestions"
  return 0
}

# --- Surfing ---

# Debian ships firefox-esr; Ubuntu ships firefox.
_install_firefox() {
  if apt-cache show firefox-esr >/dev/null 2>&1; then
    apt_install firefox-esr
  else
    apt_install firefox
  fi
}

# --- Web Tools ---

_install_nikto() {
  apt_install libnet-ssleay-perl libjson-perl &&
    _install_git nikto https://github.com/sullo/nikto &&
    run_step sudo ln -sf "$HAKPAK_OPT/nikto/program/nikto.pl" /usr/local/bin/nikto
}

_install_wpscan() {
  if has_command wpscan; then
    log_ok "wpscan already installed"
    return 0
  fi
  apt_install ruby-full ruby-dev build-essential libcurl4-openssl-dev zlib1g-dev &&
    run_step sudo gem install wpscan
}

# --- Pentest Tools ---

# Answer "yes" to "Should non-superusers be able to capture packets?" and
# add you to the wireshark group (takes effect at your next login).
_install_wireshark() {
  run_step sudo sh -c 'echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections' &&
    apt_install wireshark tcpdump &&
    run_step sudo usermod -aG wireshark "$(id -un)"
}

_install_metasploit() {
  if has_command msfconsole; then
    log_ok "metasploit already installed"
    return 0
  fi
  local tmp installer rc
  tmp="$(make_temp_dir)" || return 1
  installer="$tmp/msfinstall"
  run_step curl -fsSL -o "$installer" https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb &&
    run_step chmod 755 "$installer" &&
    run_step sudo "$installer"
  rc=$?
  run_step rm -rf "$tmp"
  return $rc
}

_install_exploitdb() {
  _install_git exploitdb https://gitlab.com/exploit-database/exploitdb &&
    run_step sudo ln -sf "$HAKPAK_OPT/exploitdb/searchsploit" /usr/local/bin/searchsploit
}

_install_nuclei() {
  _install_go nuclei github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest &&
    run_step "$GOPATH/bin/nuclei" -update-templates
}
