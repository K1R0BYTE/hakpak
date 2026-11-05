#!/usr/bin/env bats
# Tests for the install module (install/lib.sh).
# Most run through the dry-run adapter; the failure tests use the real adapter
# with stub commands on PATH.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  mkdir -p "$HAKPAK_OPT"
  : > "$HAKPAK_DRY_RUN_LOG"
}

lib() {
  # shellcheck source=/dev/null
  source "$REPO/install/lib.sh"
}

recorded() {
  grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG" || {
    echo "expected command containing: $1"
    echo "--- recorded:"
    cat "$HAKPAK_DRY_RUN_LOG"
    return 1
  }
}

not_recorded() {
  if grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG"; then
    echo "did not expect: $1"
    cat "$HAKPAK_DRY_RUN_LOG"
    return 1
  fi
}

@test "apt installs the named package non-interactively" {
  lib
  install_tool apt nmap
  recorded "DEBIAN_FRONTEND=noninteractive apt-get install -y nmap"
}

@test "apt installs a package list under one name" {
  lib
  install_tool apt sniffers "wireshark tcpdump"
  recorded "apt-get install -y wireshark tcpdump"
}

@test "go installs a module with go install into the hakpak GOPATH" {
  lib
  install_tool go nuclei github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
  recorded "go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  [ "$GOPATH" = "$HAKPAK_OPT/go" ]
}

@test "go skips a tool whose binary is already in GOPATH/bin" {
  mkdir -p "$HAKPAK_OPT/go/bin"
  touch "$HAKPAK_OPT/go/bin/ffuf"; chmod +x "$HAKPAK_OPT/go/bin/ffuf"
  lib
  install_tool go ffuf github.com/ffuf/ffuf/v2@latest
  not_recorded "go install"
}

@test "pipx installs a python tool" {
  lib
  install_tool pipx hakpak-test-tool
  recorded "pipx install hakpak-test-tool"
}

@test "pipx skips a command that already exists" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/bin/hakpak-test-tool"
  chmod +x "$BATS_TEST_TMPDIR/bin/hakpak-test-tool"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  lib
  install_tool pipx hakpak-test-tool
  not_recorded "pipx install"
}

@test "pipx can install from a source other than the name" {
  lib
  install_tool pipx interlace git+https://example.test/Interlace
  recorded "pipx install git+https://example.test/Interlace"
}

@test "gem installs a ruby tool" {
  lib
  install_tool gem wpscan
  recorded "gem install wpscan"
}

@test "git makes a shallow clone into /opt/<name>" {
  lib
  install_tool git exploitdb https://gitlab.com/exploit-database/exploitdb
  recorded "git clone --depth 1 https://gitlab.com/exploit-database/exploitdb $HAKPAK_OPT/exploitdb"
}

@test "git clones into an explicit destination" {
  lib
  install_tool git seclists https://github.com/danielmiessler/SecLists "$HAKPAK_OPT/wordlists/seclists"
  recorded "$HAKPAK_OPT/wordlists/seclists"
}

@test "git skips a destination that already exists" {
  mkdir -p "$HAKPAK_OPT/exploitdb/.git"
  lib
  install_tool git exploitdb https://gitlab.com/exploit-database/exploitdb
  not_recorded "git clone"
}

@test "venv clones, creates a venv and installs requirements into it" {
  lib
  install_tool venv subdomainizer https://github.com/nsonaniya2010/SubDomainizer
  recorded "git clone --depth 1 https://github.com/nsonaniya2010/SubDomainizer $HAKPAK_OPT/subdomainizer"
  recorded "python3 -m venv $HAKPAK_OPT/subdomainizer/.venv"
  recorded "$HAKPAK_OPT/subdomainizer/.venv/bin/pip install -r $HAKPAK_OPT/subdomainizer/requirements.txt"
  not_recorded "sudo pip"
}

@test "url downloads a file to its destination" {
  lib
  install_tool url linpeas https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh "$HAKPAK_OPT/privesc/linpeas.sh"
  recorded "curl -fsSL -o $HAKPAK_OPT/privesc/linpeas.sh https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh"
}

@test "url keeps a URL with & as one argument" {
  lib
  install_tool url thing 'https://example.test/dl?product=pro&type=Linux' "$HAKPAK_OPT/thing"
  recorded 'https://example.test/dl\?product=pro\&type=Linux'
}

@test "custom calls the named function" {
  lib
  _install_demo() { run_step echo demo-ran; }
  install_tool custom demo _install_demo
  recorded "echo demo-ran"
}

@test "dry run changes nothing on disk" {
  lib
  install_tool git exploitdb https://gitlab.com/exploit-database/exploitdb
  install_tool url fuzz https://example.test/fuzz.txt "$HAKPAK_OPT/wordlists/fuzz.txt"
  [ ! -e "$HAKPAK_OPT/exploitdb" ]
  [ ! -e "$HAKPAK_OPT/wordlists" ]
}

@test "unknown kind is reported as a failure" {
  lib
  run install_tool snap foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool kind: snap"* ]]
}

@test "summary succeeds when nothing failed" {
  lib
  install_tool apt nmap
  run install_summary
  [ "$status" -eq 0 ]
}

@test "one failing tool does not stop the next, and the summary lists it" {
  unset HAKPAK_DRY_RUN
  stubs="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stubs"
  printf '#!/bin/sh\n[ "$2" = "broken" ] && exit 1\necho "$@" >> "%s/pipx.calls"\n' "$BATS_TEST_TMPDIR" > "$stubs/pipx"
  chmod +x "$stubs/pipx"
  PATH="$stubs:$PATH"
  lib
  install_tool pipx broken || true
  install_tool pipx hakpak-test-tool
  grep -qF "install hakpak-test-tool" "$BATS_TEST_TMPDIR/pipx.calls"
  run install_summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken"* ]]
  [[ "$output" != *"hakpak-test-tool"* ]]
}

@test "HAKPAK_ROOT is the repo root" {
  lib
  [ "$HAKPAK_ROOT" = "$REPO" ]
}

# --- section scripts, end to end through the dry run ---

section() {
  # Safety: only run a section script that goes through the install module,
  # so a test can never run real installs.
  grep -q 'lib.sh' "$REPO/install/$1" || { echo "$1 does not source lib.sh"; return 1; }
  run bash "$REPO/install/$1"
}

@test "every section script runs cleanly in dry run" {
  for s in system.sh enviroment.sh basic.sh surfing.sh web-soft.sh pentest-soft.sh mitm.sh wordlists.sh wsl.sh; do
    : > "$HAKPAK_DRY_RUN_LOG"
    section "$s"
    [ "$status" -eq 0 ] || { echo "$s failed: $output"; return 1; }
  done
}

@test "pentest section installs nmap" {
  section pentest-soft.sh
  recorded "apt-get install -y nmap"
}

@test "pentest section uses current sources for moved tools" {
  section pentest-soft.sh
  recorded "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  recorded "gitlab.com/exploit-database/exploitdb"
  recorded "peass-ng/PEASS-ng/releases/latest/download/linpeas.sh"
  recorded "github.com/projectdiscovery/asnmap/cmd/asnmap@latest"
}

@test "web section no longer installs Burp" {
  section web-soft.sh
  not_recorded "burp"
}

@test "environment section installs Go from go.dev, not the distro" {
  section enviroment.sh
  recorded "go.dev/dl/"
  not_recorded "install -y golang"
}

@test "no install script uses go get, sudo pip or setup.py install" {
  run grep -nE 'go get|sudo pip|pip3? install -r /opt|setup\.py install' "$REPO"/install/*.sh
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
}

@test "section scripts don't call apt, go, pip or git directly" {
  run grep -nE '^\s*(sudo )?(apt|apt-get|go|pip3?|git) ' \
    "$REPO"/install/{system,enviroment,basic,surfing,web-soft,pentest-soft,mitm,wordlists,wsl}.sh
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
}

@test "section scripts don't define their own logger" {
  run grep -n 'colorecho()' "$REPO"/install/{system,enviroment,basic,surfing,web-soft,pentest-soft,mitm,wordlists,wsl}.sh
  [ "$status" -ne 0 ]
}

# --- review fixes ---

@test "venv retries requirements when an earlier install didn't finish" {
  mkdir -p "$HAKPAK_OPT/subdomainizer/.venv" "$HAKPAK_OPT/subdomainizer/.git"
  lib
  install_tool venv subdomainizer https://github.com/nsonaniya2010/SubDomainizer
  recorded "pip install -r $HAKPAK_OPT/subdomainizer/requirements.txt"
}

@test "venv is skipped once requirements installed" {
  mkdir -p "$HAKPAK_OPT/subdomainizer/.venv" "$HAKPAK_OPT/subdomainizer/.git"
  touch "$HAKPAK_OPT/subdomainizer/.venv/.hakpak-installed"
  lib
  install_tool venv subdomainizer https://github.com/nsonaniya2010/SubDomainizer
  not_recorded "pip install"
}

@test "a failed step is counted in the summary" {
  unset HAKPAK_DRY_RUN
  lib
  step "wsl.conf" false || true
  run install_summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"wsl.conf"* ]]
}

@test "make_temp_dir creates nothing in dry run" {
  lib
  d="$(make_temp_dir)"
  [ ! -e "$d" ]
}

@test "make_temp_dir makes a private dir in a real run" {
  unset HAKPAK_DRY_RUN
  lib
  d="$(make_temp_dir)"
  [ -d "$d" ]
  [ "$(stat -c %a "$d")" = "700" ]
  rm -rf "$d"
}

@test "basic section installs oh-my-zsh by git clone, then its plugins" {
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  section basic.sh
  recorded "git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git $HOME/.oh-my-zsh"
  recorded "zsh-autosuggestions"
}

@test "basic section: re-linking keeps the original backup" {
  unset HAKPAK_DRY_RUN
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  echo original > "$HOME/.zshrc"
  lib
  eval "$(sed -n '/^_link_home_config()/,/^}/p' "$REPO/install/basic.sh")"
  _link_home_config "$REPO/configs/zsh/.zshrc" "$HOME/.zshrc"
  _link_home_config "$REPO/configs/zsh/.zshrc" "$HOME/.zshrc"
  [ "$(cat "$HOME/.zshrc.bak")" = "original" ]
  [ "$(readlink "$HOME/.zshrc")" = "$REPO/configs/zsh/.zshrc" ]
}

# --- Surfing and MiTM sections ---

@test "surfing section installs the browsers" {
  section surfing.sh
  recorded "torbrowser-launcher"
  grep -qE 'apt-get install -y (firefox-esr|firefox)$' "$HAKPAK_DRY_RUN_LOG"
}

@test "basic section no longer installs the browsers" {
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  section basic.sh
  not_recorded "torbrowser-launcher"
  not_recorded "firefox"
}

@test "mitm section installs the access point and interception tools" {
  section mitm.sh
  recorded "apt-get install -y hostapd dnsmasq-base iptables tcpdump iw"
  recorded "pipx install mitmproxy"
}

@test "tcpdump is in both pentest and mitm" {
  section pentest-soft.sh
  recorded "tcpdump"
}

@test "wordlists section no longer downloads fuzz.txt" {
  section wordlists.sh
  not_recorded "fuzz.txt"
}

@test "environment section uses python3-venv, not virtualenv" {
  section enviroment.sh
  recorded "python3-venv"
  not_recorded "virtualenv"
}

@test "setup.sh runs the new sections" {
  grep -q 'bash surfing.sh' "$REPO/install/setup.sh"
  grep -q 'bash mitm.sh' "$REPO/install/setup.sh"
}

# --- dnsmasq swap and sudo handling ---

@test "system section no longer installs isc-dhcp-server" {
  section system.sh
  not_recorded "isc-dhcp-server"
}

@test "system section doesn't take over all of /opt" {
  section system.sh
  not_recorded "chown -R"
}

@test "wsl section sets up dnsmasq for DHCP instead of isc-dhcp-server" {
  section wsl.sh
  recorded "apt-get install -y dnsmasq"
  recorded "install -m 644 $REPO/configs/dnsmasq.conf /etc/dnsmasq.d/hakpak.conf"
  not_recorded "dhcpd.conf"
}

@test "dnsmasq config is DHCP only, so it doesn't take port 53" {
  grep -qx 'port=0' "$REPO/configs/dnsmasq.conf"
  grep -q '^dhcp-range=172.21.48.10,172.21.48.20' "$REPO/configs/dnsmasq.conf"
  [ ! -e "$REPO/configs/dhcpd.conf" ]
}

@test "wsl section lets xrdp read its TLS key" {
  section wsl.sh
  recorded "adduser xrdp ssl-cert"
}

@test "pentest section lets your user capture with wireshark" {
  section pentest-soft.sh
  recorded "debconf-set-selections"
  recorded "usermod -aG wireshark"
}

@test "sections refuse to run as root" {
  unset HAKPAK_DRY_RUN
  lib
  _HAKPAK_EUID=0 run require_normal_user
  [ "$status" -ne 0 ]
  [[ "$output" == *"not as root"* ]]
}

@test "sections run as a normal user" {
  unset HAKPAK_DRY_RUN
  lib
  _HAKPAK_EUID=1000 run require_normal_user
  [ "$status" -eq 0 ]
}

@test "every section script checks it isn't run as root" {
  for s in system enviroment basic surfing web-soft pentest-soft mitm wordlists wsl; do
    grep -q '^require_normal_user' "$REPO/install/$s.sh" || { echo "$s.sh"; return 1; }
  done
}

@test "a destination under a directory you can't write is made with sudo and handed to you" {
  [ "$(id -u)" -ne 0 ] || skip "root can write anywhere"
  mkdir -p "$BATS_TEST_TMPDIR/ro"
  chmod 555 "$BATS_TEST_TMPDIR/ro"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/ro"
  lib
  install_tool git exploitdb https://gitlab.com/exploit-database/exploitdb
  recorded "sudo mkdir -p $HAKPAK_OPT"
  recorded "sudo chown"
}

@test "README says to run setup.sh without sudo" {
  grep -qi 'not with sudo' "$REPO/README.md"
}
