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
  # Read the version file instead of running go, which writes telemetry
  # counters to your home even for `go env`.
  if [ -x /usr/local/go/bin/go ] && [ "$(head -n1 /usr/local/go/VERSION 2>/dev/null)" = "$version" ]; then
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

# A user's login shell, from the passwd database. Empty when there is no entry.
_login_shell() {
  getent passwd "$1" 2>/dev/null | cut -d: -f7
}

# Make zsh your login shell unless it already is. The name comes from
# `id -un`, not $USER: only a login sets $USER, so a container or sandbox
# shell can have it empty. The change is made with usermod, not chsh: chsh
# authenticates through PAM even under sudo, and asks for a password when
# root's own shell isn't in /etc/shells (nologin, as in some containers and
# sandboxes). A shell that can't be changed is a warning, not a failed tool,
# and the next run tries again.
_use_zsh_as_login_shell() {
  local user zsh
  user="$(id -un 2>/dev/null)"
  zsh="$(command -v zsh || echo /usr/bin/zsh)"
  if [ -n "$user" ]; then
    case "$(_login_shell "$user")" in */zsh) return 0 ;; esac
    run_step sudo usermod -s "$zsh" "$user" && return 0
  fi
  log "Couldn't make zsh your login shell. To do it yourself: sudo usermod -s $zsh ${user:-<your user>}"
  return 0
}

# Plugins go inside oh-my-zsh, so they're cloned only once it's there.
_install_oh_my_zsh() {
  local zsh_dir="${HOME}/.oh-my-zsh"
  local plugins="$zsh_dir/custom/plugins"
  if [ -f "$zsh_dir/oh-my-zsh.sh" ]; then
    log_ok "oh-my-zsh already installed"
  else
    need_command git &&
      run_step git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$zsh_dir" || return 1
  fi
  _use_zsh_as_login_shell
  # Each plugin is its own tool, so a failed clone is reported by its name.
  install_tool git zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins/zsh-syntax-highlighting"
  install_tool git zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions "$plugins/zsh-autosuggestions"
  return 0
}

# Starship, the prompt that draws the hakpak themes (configs/starship), from
# its release tarball, checked against the release's checksum. Debian 12 and
# Ubuntu before 25.04 have no apt package. Without it zsh keeps the
# oh-my-zsh theme.
_install_starship() {
  local arch tag asset
  if has_command starship; then
    log_ok "starship already installed"
    return 0
  fi
  # top is the first section: curl may not be there yet.
  need_command curl || return 1
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) echo "starship: hakpak has no build for $(uname -m)"; return 1 ;;
  esac
  tag="$(_github_latest_tag starship/starship)" || return 1
  asset="starship-$arch-unknown-linux-musl.tar.gz"
  _install_release_binary starship \
    "https://github.com/starship/starship/releases/download/$tag" \
    "$asset" "$asset.sha256"
}

# --- Top ---

# Claude Code from Anthropic's signed apt repo, stable channel (about a week
# behind the latest release). A `claude` you already have, however it was
# installed, is left as it is. The repo key must be Anthropic's release key:
# its fingerprint is the one in the Claude Code setup docs
# (https://code.claude.com/docs/en/setup). apt installs don't update
# themselves: `sudo apt update && sudo apt upgrade claude-code`.
# The skills are linked on every run, so a new skill in the repo shows up.
_install_claude_code() {
  if has_command claude; then
    log_ok "claude-code already installed"
  else
    add_apt_repo claude-code \
      https://downloads.claude.ai/keys/claude-code.asc \
      /etc/apt/keyrings/claude-code.gpg \
      'deb [signed-by=/etc/apt/keyrings/claude-code.gpg] https://downloads.claude.ai/claude-code/apt/stable stable main' \
      31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE &&
      apt_install claude-code || return 1
  fi
  _link_claude_skills
}

_dir_is_writable() {
  [ -w "$1" ]
}

# Link every skill in the repo's .claude/skills (a directory with a SKILL.md)
# into your Claude Code skills directory, so Claude Code loads it in any
# project and `git pull` updates it. A skill of the same name that you
# already have (a directory, or your own link) is kept. A broken link that
# hakpak made is repaired or removed: one left by a clone that has moved,
# or by a skill the repo no longer has. Safe to re-run.
_link_claude_skills() {
  local src="$HAKPAK_ROOT/.claude/skills"
  local dest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
  local dir name target to rc=0
  # In a Docker Sandbox this directory is the host's shared skills store,
  # mounted read-only unless the sandbox was created with --skills=readwrite.
  if [ -d "$dest" ] && ! _dir_is_writable "$dest"; then
    log_ok "skills: $dest is read-only (a sandbox's shared skills store), so hakpak's skills are not linked. On the host, sbx skills import or sbx skills add puts skills there."
    return 0
  fi
  # Links to skills that are gone from this clone.
  for target in "$dest"/*; do
    if [ ! -L "$target" ] || [ -e "$target" ]; then continue; fi
    case "$(readlink "$target")" in
      "$src"/*) run_step rm -f "$target" || rc=1 ;;
    esac
  done
  for dir in "$src"/*/; do
    dir="${dir%/}"
    [ -f "$dir/SKILL.md" ] || continue
    name="${dir##*/}"
    target="$dest/$name"
    to=""
    [ -L "$target" ] && to="$(readlink "$target")"
    if [ "$to" = "$dir" ]; then
      log_ok "skill $name already linked"
    elif [ -e "$target" ]; then
      log_ok "skill $name: kept your own at $target${to:+ -> $to}"
    elif [ -n "$to" ] && [[ "$to" != */.claude/skills/"$name" ]]; then
      log_ok "skill $name: kept your own link at $target -> $to (broken)"
    else
      { [ -d "$dest" ] || run_step mkdir -p "$dest"; } &&
        run_step ln -sfn "$dir" "$target" || rc=1
    fi
  done
  return "$rc"
}

# --- Dev ---

# Debian and Ubuntu name fd's command fdfind (another package owns fd).
# It is linked as fd in ~/.local/bin, so scripts and agents find it under
# the name its docs use, not only a shell with an alias.
_install_fd() {
  local bin
  if has_command fd; then
    log_ok "fd already installed"
    return 0
  fi
  has_command fdfind || apt_install fd-find || return 1
  bin="$(command -v fdfind || echo /usr/bin/fdfind)"
  { [ -d "$HOME/.local/bin" ] || run_step mkdir -p "$HOME/.local/bin"; } &&
    run_step ln -sfn "$bin" "$HOME/.local/bin/fd"
}

# True when <file> has exactly this sha256: _sha256_is <file> <hash>
# For a download whose release publishes no checksum: the hash is kept in
# hakpak, next to the version it belongs to.
_sha256_is() {
  local file="$1" want="$2" got
  got="$(sha256sum "$file" | awk '{ print $1 }')" || return 1
  if [ "${want,,}" != "$got" ]; then
    echo "checksum mismatch for $(basename "$file")"
    return 1
  fi
}

# uv, Astral's Python package and tool manager, from its latest release
# tarball, checked against the checksum published next to it. uv and uvx
# go in /usr/local/bin. A uv you already have is kept.
_install_uv_release() {
  local arch asset base tmp rc
  if has_command uv; then
    log_ok "uv already installed"
    return 0
  fi
  need_command curl || return 1
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) echo "uv: hakpak has no build for $(uname -m)"; return 1 ;;
  esac
  asset="uv-$arch-unknown-linux-gnu"
  base="https://github.com/astral-sh/uv/releases/latest/download"
  tmp="$(make_temp_dir)" || return 1
  run_step curl -fsSL -o "$tmp/$asset.tar.gz" "$base/$asset.tar.gz" &&
    run_step curl -fsSL -o "$tmp/$asset.tar.gz.sha256" "$base/$asset.tar.gz.sha256" &&
    run_step verify_sha256 "$tmp/$asset.tar.gz" "$tmp/$asset.tar.gz.sha256" "$asset.tar.gz" &&
    run_step tar -C "$tmp" --no-same-owner -xzf "$tmp/$asset.tar.gz" &&
    run_step sudo install -m 755 "$tmp/$asset/uv" /usr/local/bin/uv &&
    run_step sudo install -m 755 "$tmp/$asset/uvx" /usr/local/bin/uvx
  rc=$?
  run_step rm -rf "$tmp"
  return $rc
}

# Python from uv: a prebuilt interpreter in your home, next to the system
# python3, which stays the default. uv picks it for `uv run`, `uv venv` and
# the uv tools. Installing a version you already have changes nothing.
_HAKPAK_PYTHON=3.13
_install_uv_python() {
  run_step uv python install "$_HAKPAK_PYTHON"
}

# fnm, the Node version manager. Its releases publish no checksums, so the
# version is pinned here with the sha256 of each zip (taken from the release
# assets on GitHub). To update: change the version and both hashes.
_FNM_VERSION=1.39.0
_install_fnm() {
  local asset sha tmp rc
  if has_command fnm; then
    log_ok "fnm already installed"
    return 0
  fi
  case "$(_go_arch)" in
    amd64) asset=fnm-linux.zip sha=7807664f39d39fc518da1c35ba0181e4b3267603c4b1dedeb4b5fc6ae440a224 ;;
    arm64) asset=fnm-arm64.zip sha=4eaff58b2c5bf30d0934027572dd0b5bbb60d2a1af309230b53662d4b1d45599 ;;
    *) echo "fnm: hakpak has no build for $(uname -m)"; return 1 ;;
  esac
  need_command curl && need_command unzip || return 1
  tmp="$(make_temp_dir)" || return 1
  run_step curl -fsSL -o "$tmp/$asset" "https://github.com/Schniz/fnm/releases/download/v$_FNM_VERSION/$asset" &&
    run_step _sha256_is "$tmp/$asset" "$sha" &&
    run_step unzip -q -o "$tmp/$asset" fnm -d "$tmp" &&
    run_step sudo install -m 755 "$tmp/fnm" /usr/local/bin/fnm
  rc=$?
  run_step rm -rf "$tmp"
  return $rc
}

# Node from fnm, in ~/.local/share/fnm (the directory system/.dev puts on
# PATH), as the default version. pnpm comes through corepack, which ships
# with Node, and is downloaded now, not at its first use: nothing is
# installed with npm -g.
_HAKPAK_NODE=22
_install_node() {
  local dir="$HOME/.local/share/fnm" bin
  bin="$dir/aliases/default/bin"
  run_step env FNM_DIR="$dir" fnm install "$_HAKPAK_NODE" &&
    run_step env FNM_DIR="$dir" fnm default "$_HAKPAK_NODE" &&
    run_step env PATH="$bin:$PATH" corepack enable pnpm &&
    run_step env PATH="$bin:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack prepare pnpm@latest --activate
}

# Rust from rustup-init, the installer binary itself (not the script from
# sh.rustup.rs), checked against the sha256 published next to it. Stable
# toolchain with the default profile, which has clippy and rustfmt, in
# ~/.cargo and ~/.rustup. Your shell files are not edited: system/.dev puts
# ~/.cargo/bin on PATH. A rustup you already have is kept.
_install_rust() {
  local triple base tmp rc
  if has_command rustup || [ -x "$HOME/.cargo/bin/rustup" ]; then
    log_ok "rust already installed"
    return 0
  fi
  need_command curl || return 1
  case "$(uname -m)" in
    x86_64) triple=x86_64-unknown-linux-gnu ;;
    aarch64|arm64) triple=aarch64-unknown-linux-gnu ;;
    *) echo "rust: hakpak has no build for $(uname -m)"; return 1 ;;
  esac
  base="https://static.rust-lang.org/rustup/dist/$triple"
  tmp="$(make_temp_dir)" || return 1
  run_step curl -fsSL -o "$tmp/rustup-init" "$base/rustup-init" &&
    run_step curl -fsSL -o "$tmp/rustup-init.sha256" "$base/rustup-init.sha256" &&
    run_step verify_sha256 "$tmp/rustup-init" "$tmp/rustup-init.sha256" &&
    run_step chmod 700 "$tmp/rustup-init" &&
    run_step "$tmp/rustup-init" -y --no-modify-path --profile default --default-toolchain stable
  rc=$?
  run_step rm -rf "$tmp"
  return $rc
}

# The Claude Code plugin marketplaces the dev plugins come from. A
# marketplace is a catalogue: registering one installs nothing. hakpak's own
# (.claude-plugin/marketplace.json in this repo) lists skills that are
# published as a plain skill repo, so they install as plugins too; that
# works where ~/.claude/skills is read-only, as in a Docker Sandbox. Adding
# a marketplace you already have changes nothing.
_install_claude_marketplaces() {
  local source rc=0
  _need_claude "the plugin marketplaces" || return 1
  for source in trailofbits/skills trailofbits/skills-curated anthropics/skills "$HAKPAK_ROOT"; do
    run_step claude plugin marketplace add "$source" || rc=1
  done
  return "$rc"
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

# --- Cloud ---

# The distro codename (bookworm, noble) from os-release.
# HAKPAK_OS_RELEASE points it at another file (tests use this).
_distro_codename() {
  local codename
  # shellcheck disable=SC1090 # os-release is a plain key=value file
  codename="$(. "${HAKPAK_OS_RELEASE:-/etc/os-release}" 2>/dev/null && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")"
  if ! [[ "$codename" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "can't tell the distro codename from ${HAKPAK_OS_RELEASE:-/etc/os-release}" >&2
    return 1
  fi
  echo "$codename"
}

# Latest release tag of a GitHub repo (v3.90.1). github.com answers
# releases/latest with JSON when asked for it, without the rate-limited API.
# A tag that isn't a plain version is refused: it goes into paths and URLs.
_github_latest_tag() {
  local repo="$1" tag
  if [ "${HAKPAK_DRY_RUN:-0}" = "1" ]; then
    echo "v0.0.0"
    return 0
  fi
  tag="$(curl -fsSL -H 'Accept: application/json' "https://github.com/$repo/releases/latest" |
    sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p')"
  if ! [[ "$tag" =~ ^v?[0-9]+(\.[0-9]+)*$ ]]; then
    echo "could not find the latest release of $repo" >&2
    return 1
  fi
  echo "$tag"
}

# CPU name in release asset names (amd64, arm64); other CPUs have no build.
_release_arch() {
  local arch
  arch="$(_go_arch)"
  case "$arch" in
    amd64|arm64) echo "$arch" ;;
    *) echo "$1 has no build for $(uname -m)" >&2; return 1 ;;
  esac
}

# Download one release asset and its checksum manifest, check the asset,
# and install the binary as /usr/local/bin/<name>. A .tar.gz asset is
# unpacked first and its <name> file installed:
#   _install_release_binary <name> <release-url> <asset> <checksums-file>
_install_release_binary() {
  local name="$1" base="$2" asset="$3" sums="$4" tmp bin rc
  tmp="$(make_temp_dir)" || return 1
  bin="$tmp/$asset"
  run_step curl -fsSL -o "$tmp/$asset" "$base/$asset" &&
    run_step curl -fsSL -o "$tmp/$sums" "$base/$sums" &&
    run_step verify_sha256 "$tmp/$asset" "$tmp/$sums" "$asset"
  rc=$?
  if [ "$rc" -eq 0 ] && [[ "$asset" == *.tar.gz ]]; then
    run_step mkdir "$tmp/unpacked" &&
      run_step tar -C "$tmp/unpacked" --no-same-owner -xzf "$tmp/$asset"
    rc=$?
    bin="$tmp/unpacked/$name"
  fi
  if [ "$rc" -eq 0 ]; then
    run_step sudo install -m 755 "$bin" "/usr/local/bin/$name"
    rc=$?
  fi
  run_step rm -rf "$tmp"
  return $rc
}

# AWS CLI v2 from AWS's zip, checked against its signature with the AWS CLI
# Team key in install/keys/aws-cli.asc. AWS ships no apt package for v2.
# An existing install (in /usr/local/aws-cli) is updated in place.
_install_aws_cli() {
  local arch tmp url rc
  local -a update=()
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) echo "the AWS CLI has no build for $(uname -m)"; return 1 ;;
  esac
  [ -d /usr/local/aws-cli ] && update=(--update)
  if ! has_command unzip; then
    apt_install unzip || return 1
  fi
  if ! has_command gpg || ! has_command gpgv; then
    apt_install gnupg gpgv || return 1
  fi
  url="https://awscli.amazonaws.com/awscli-exe-linux-$arch.zip"
  tmp="$(make_temp_dir)" || return 1
  run_step curl -fsSL -o "$tmp/awscliv2.zip" "$url" &&
    run_step curl -fsSL -o "$tmp/awscliv2.zip.sig" "$url.sig" &&
    run_step verify_gpg_signature "$HAKPAK_ROOT/install/keys/aws-cli.asc" "$tmp/awscliv2.zip.sig" "$tmp/awscliv2.zip" &&
    run_step unzip -q "$tmp/awscliv2.zip" -d "$tmp" &&
    run_step sudo "$tmp/aws/install" "${update[@]}"
  rc=$?
  run_step rm -rf "$tmp"
  return $rc
}

# google-cloud-cli from Google's apt repo. The repo is the same for every
# Debian and Ubuntu release.
_install_gcloud() {
  if has_command gcloud; then
    log_ok "gcloud already installed"
    return 0
  fi
  add_apt_repo google-cloud-sdk \
    https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    /usr/share/keyrings/cloud.google.gpg \
    'deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main' &&
    apt_install google-cloud-cli
}

# azure-cli from Microsoft's apt repo. Microsoft publishes it only for
# supported Debian and Ubuntu releases, so the repo is checked for your
# codename before it's added; on any other distro (Kali) this fails.
_install_azure_cli() {
  local codename repo=https://packages.microsoft.com/repos/azure-cli
  if has_command az; then
    log_ok "az already installed"
    return 0
  fi
  codename="$(_distro_codename)" || return 1
  if ! run_step curl -fsSI -o /dev/null "$repo/dists/$codename/Release"; then
    echo "Microsoft doesn't publish the Azure CLI for $codename (supported Debian and Ubuntu releases only)"
    return 1
  fi
  add_apt_repo azure-cli \
    https://packages.microsoft.com/keys/microsoft.asc \
    /etc/apt/keyrings/microsoft.gpg \
    "deb [signed-by=/etc/apt/keyrings/microsoft.gpg] $repo/ $codename main" &&
    apt_install azure-cli
}

# Latest stable kubectl from dl.k8s.io, checked against its .sha256. The
# pkgs.k8s.io apt repo pins one minor version per repo URL, so it isn't used.
_install_kubectl() {
  local arch version base tmp rc
  arch="$(_go_arch)" || { echo "unsupported CPU: $(uname -m)"; return 1; }
  if [ "${HAKPAK_DRY_RUN:-0}" = "1" ]; then
    version="${HAKPAK_KUBECTL_VERSION:-v0.0.0}"
  else
    version="${HAKPAK_KUBECTL_VERSION:-$(curl -fsSL https://dl.k8s.io/release/stable.txt)}"
  fi
  if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "could not find the latest kubectl version"
    return 1
  fi
  if [ -x /usr/local/bin/kubectl ] &&
    /usr/local/bin/kubectl version --client 2>/dev/null | grep -qxF "Client Version: $version"; then
    log_ok "kubectl $version already installed"
    return 0
  fi
  base="https://dl.k8s.io/release/$version/bin/linux/$arch"
  tmp="$(make_temp_dir)" || return 1
  run_step curl -fsSL -o "$tmp/kubectl" "$base/kubectl" &&
    run_step curl -fsSL -o "$tmp/kubectl.sha256" "$base/kubectl.sha256" &&
    run_step verify_sha256 "$tmp/kubectl" "$tmp/kubectl.sha256" &&
    run_step sudo install -m 755 "$tmp/kubectl" /usr/local/bin/kubectl
  rc=$?
  run_step rm -rf "$tmp"
  return $rc
}

# Kubescape release binary, checked against the release's checksums.sha256
# (what upstream's install.sh does, without its edits to your PATH).
_install_kubescape() {
  local arch tag
  if has_command kubescape; then
    log_ok "kubescape already installed"
    return 0
  fi
  arch="$(_release_arch kubescape)" || return 1
  tag="$(_github_latest_tag kubescape/kubescape)" || return 1
  _install_release_binary kubescape \
    "https://github.com/kubescape/kubescape/releases/download/$tag" \
    "kubescape_${tag#v}_linux_${arch}" checksums.sha256
}

# --- CI/CD ---

# TruffleHog release tarball, checked against the release's checksums.
# `go install` doesn't work: its go.mod has replace directives.
_install_trufflehog() {
  local arch tag
  if has_command trufflehog; then
    log_ok "trufflehog already installed"
    return 0
  fi
  arch="$(_release_arch trufflehog)" || return 1
  tag="$(_github_latest_tag trufflesecurity/trufflehog)" || return 1
  _install_release_binary trufflehog \
    "https://github.com/trufflesecurity/trufflehog/releases/download/$tag" \
    "trufflehog_${tag#v}_linux_${arch}.tar.gz" "trufflehog_${tag#v}_checksums.txt"
}
