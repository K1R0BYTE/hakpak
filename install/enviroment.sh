#!/usr/bin/env bash
# Environment section: Python, Jython and Go.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Python: system pip stays untouched (PEP 668); tools go through pipx or a venv.
install_tool apt python "python3-pip python3-venv pipx virtualenv python3-requests python3-setuptools"
install_tool apt jython

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
  tarball="${TMPDIR:-/tmp}/hakpak-${version}.linux-${arch}.tar.gz"
  run_step curl -fsSL -o "$tarball" "https://go.dev/dl/${version}.linux-${arch}.tar.gz" &&
    run_step sudo rm -rf /usr/local/go &&
    run_step sudo tar -C /usr/local -xzf "$tarball" &&
    run_step rm -f "$tarball"
}
install_tool custom go _install_go_toolchain

install_summary
