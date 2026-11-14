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

With no arguments `setup.sh` opens a menu that lists each section with the tools it installs: move with the arrow keys (or j/k), tick sections with space (`a` ticks all), press Enter to install the ticked ones, or q to quit. The menu needs a terminal; in scripts and CI, name the sections or pass `all`. You can also name sections to install only those, in install order, or pass `all`; `--dry-run` prints what would run and changes nothing:

```
bash setup.sh                        # menu: tick the sections to install
bash setup.sh web pentest            # only Web Tools and Pentest Tools
bash setup.sh all                    # every section
bash setup.sh --dry-run all          # everything, without installing
bash setup.sh --help                 # the section names
```

Sections: `top`, `dev`, `system`, `environment`, `basic`, `surfing`, `web`, `pentest`, `cloud`, `cicd`, `mitm`, `wordlists`, `wsl`, `rdp`. If one fails, the rest still run and `setup.sh` lists the failed sections at the end.

Run `setup.sh` as your normal user, not with sudo. Your user needs sudo rights; the scripts ask for your password only for the steps that need root (apt packages, `/usr/local`, `/etc`). Everything else installs as you: Go tools into `/opt/go`, pipx and uv tools into `~/.local/bin`, and git tools into `/opt/<tool>`, owned by you.

When `setup.sh` has installed zsh (the `top` or `basic` section) and you ran it at a terminal, it ends by starting zsh, so you are in the new shell right away; `exit` goes back to the shell you started from. zsh also becomes your login shell, and one line added to `~/.bashrc` makes an interactive bash hand over to zsh, for places that start bash directly and never read the login shell (a container or sandbox shell). Scripts and `bash -c` are not touched, and a `bash` typed from zsh stays bash. `HAKPAK_NO_ZSH=1` switches both off.

After the install, log out and back in once: that picks up the PATH for Go and pipx tools, and the wireshark group.

You can clone it anywhere; the scripts find the repo from their own path.

If a tool fails to install, the rest keep going and each section lists what failed at the end.

Re-running a section is safe. Your own dotfiles (`.zshrc`, `.tmux.conf`, `.dircolors`) are moved to `<file>.bak` once and replaced with links into `configs/`, so later runs change nothing. Configs under `/etc` (like `/etc/wsl.conf`) are copied, not linked, because root services read them. The curated `.zsh_history` is merged into your own history instead of linked, so Ctrl+R finds those commands and what you type stays local.

The `top` section installs the [Claude Code](https://code.claude.com/docs/en/setup) CLI from Anthropic's signed apt repo, `stable` channel, after checking the repo key's fingerprint. If you already have `claude` (say, from the native installer), it is left as it is and only the skills are linked. Installed from apt it doesn't update itself: run `sudo apt update && sudo apt upgrade claude-code`. Start it with `claude` and sign in on first run.

The `dev` section sets up a developer environment, based on the tools and configs of the Trail of Bits [devcontainer](https://github.com/trailofbits/skills/tree/main/plugins/devcontainer-setup) without the container: nothing in it builds or runs one, so it fits a machine that is already a sandbox.

* Tools: ripgrep, fd, jq, delta, gh, shellcheck, shfmt, ast-grep, and the linters ruff, ty, zizmor, prek and actionlint.
* Toolchains: Python 3.13 from uv, Node 22 from fnm with pnpm, Go, and stable Rust from rustup. They install into your home (`~/.local`, `~/.cargo`), next to what the system has. No installer script is piped into a shell: uv and rustup are checked against the checksum published with them, and fnm, which publishes none, is a pinned version with its hash kept in `install/custom.sh`.
* Claude Code skills: it registers the plugin marketplaces `trailofbits/skills`, `trailofbits/skills-curated` and `anthropics/skills`, and installs the plugins listed under Dev below for your user. hakpak's own marketplace file (`.claude-plugin/marketplace.json`) lists Cloudflare's `security-audit-skill` as a plugin, so it installs the same way. `/plugin` in Claude Code shows the rest of each marketplace.
* Configs: `system/.dev` puts the tool directories on PATH, turns on npm's safer defaults (no install scripts, no package younger than a day), and adds the aliases `sg` (ast-grep) and `claude-yolo` (`claude --dangerously-skip-permissions`). git gets delta as its pager through one `include` line in your `~/.gitconfig`, and a global ignore file if you have none; delete the include line to undo it.
* Claude Code's `settings.json` is never written, and no permission mode is set for you. For a global `CLAUDE.md` and language rules, the section clones Trail of Bits' [claude-code-config](https://github.com/trailofbits/claude-code-config) to `/opt/claude-code-config`: run `claude` there, then `/trailofbits:config`.

In a Docker Sandbox (sbx) the section does three things differently. The PATH line also goes into `/etc/sandbox-persistent.sh`, which every shell there and Claude Code's own commands read. Skills come from plugins only, since `~/.claude/skills` is the host's shared skills store and is read-only by default. And when a download fails, the summary names the `sbx policy` commands to run on the host, because the sandbox's network policy is the usual cause. A sandbox loses what `dev` installed when it is removed (`sbx rm`), not when it stops.

To see what a section would do without changing anything:

```
bash setup.sh --dry-run web
```

# Toolset

Every tool is one row in [`install/toolset.txt`](install/toolset.txt): its section, how it installs (its kind), its name and where it comes from. Each section script installs its rows, and the list below is generated from the same file. To add or drop a tool, edit that file and run `tools/gen-readme`. Tools that need more than one step (`custom`) name a function in `install/custom.sh`.

<!-- toolset:start -->
## Top

* vim (apt)
* fzf (apt): Ctrl+R history search
* zsh (apt): with the hakpak config and history
* oh-my-zsh: with zsh-syntax-highlighting and zsh-autosuggestions
* starship: prompt for the hakpak themes, release binary, checksum checked
* tmux (apt): with the hakpak config
* tpm (git)
* claude-code: Claude Code CLI from Anthropic's apt repo (stable), with the skills from .claude/skills

## Dev

* build-essential (apt)
* ripgrep (apt): rg, a faster grep
* jq (apt)
* git-delta (apt): the git pager, with the hakpak git config
* gh (apt): GitHub CLI
* shellcheck (apt)
* shfmt (apt)
* fd: fd-find from apt, linked as fd
* uv: release binary, checksum checked
* python: Python 3.13 from uv
* ast-grep (uv): code search by syntax tree
* ruff (uv): Python linter and formatter
* ty (uv): Python type checker
* zizmor (uv): GitHub Actions security audit
* prek (uv): git hooks, a faster pre-commit
* fnm: Node version manager, pinned release, checksum checked
* node: Node 22 from fnm, with pnpm through corepack
* go: latest Go from go.dev, in /usr/local/go
* actionlint (go): GitHub Actions linter
* rust: stable Rust with clippy and rustfmt, from rustup-init, checksum checked
* claude-code: Claude Code CLI from Anthropic's apt repo (stable), with the skills from .claude/skills
* claude-marketplaces: trailofbits/skills, trailofbits/skills-curated, anthropics/skills and hakpak's own
* modern-python (plugin): uv, ruff, ty and pytest for Python projects
* rust-review (plugin): Rust security review
* gh-cli (plugin): sends GitHub fetches through gh
* git-cleanup (plugin): sorts and cleans local branches and worktrees
* property-based-testing (plugin)
* static-analysis (plugin): CodeQL, Semgrep and SARIF
* differential-review (plugin): security review of a diff
* security-audit (plugin): Cloudflare's security-audit-skill
* claude-code-config (git): Trail of Bits' Claude Code config; run claude there and /trailofbits:config

## System

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
* starship: prompt for the hakpak themes, release binary, checksum checked
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

## Cloud

* aws: AWS CLI v2 from AWS, signature checked
* gcloud: google-cloud-cli from Google's apt repo
* az: azure-cli from Microsoft's apt repo, supported Debian and Ubuntu releases only
* kubectl: latest stable from dl.k8s.io, checksum checked
* prowler (pipx): needs Python 3.10 to 3.13
* kubescape: release binary, checksum checked
* pacu (pipx)
* gcpwn (pipx): needs Python 3.11 or newer

## CI/CD

* trajan (go)
* gato-x (pipx)
* trufflehog: release binary, checksum checked

## MiTM

* hostapd (apt): Wi-Fi access point
* dnsmasq-base (apt): DHCP and DNS for AP clients, no system service
* iptables (apt): NAT and redirect rules
* tcpdump (apt)
* iw (apt): checks the Wi-Fi card can do AP mode
* mitmproxy (pipx)

## Wordlists

* seclists (git)

## RDP

* xfce4 (apt)
* xrdp (apt): remote desktop on port 3390
* dbus-x11 (apt)
<!-- toolset:end -->

# Themes

zsh and tmux come in a purple and black look. The prompt is drawn by [Starship](https://starship.rs), which the `basic` and `top` sections install from its release (checksum checked); Starship was picked over Powerlevel10k because each theme is one small TOML file in `configs/starship/`. If Starship isn't installed, zsh keeps the oh-my-zsh `agnoster` theme.

There are three themes, each with a matching tmux status bar in `configs/tmux/themes/`:

- `neon` (the default): solid purple and pink segments with shaded edges.
- `wireframe`: thin neon lines and colored text, no filled blocks.
- `powerline`: arrow segments with icons. It needs a [Nerd Font](https://www.nerdfonts.com/font-downloads) set in your terminal, or the arrows and icons show as empty boxes. On WSL install the font on Windows and pick it in Windows Terminal (Settings, your profile, Appearance, Font face).

```
hakpak-theme                 # list the themes, the one in use marked *
hakpak-theme wireframe       # switch
```

Switching changes the prompt of the shell you are in and the tmux status bar at once; other open shells follow when they next start. The choice is kept in `~/.config/hakpak/theme`, not in the repo. `neon` and `wireframe` work in any font. All three use 24-bit color, which Windows Terminal and most current terminals have, and expect a dark background: the black comes from your terminal's own color scheme. Command highlighting, suggestions and the Ctrl+R history search use the same palette.

tmux draws the prompt glyphs only when your locale is UTF-8; otherwise it shows them as `_`. hakpak's zsh sets `LC_CTYPE=C.UTF-8` when the environment names no UTF-8 locale (common in containers), unless you set `LC_ALL` yourself. If you start tmux from another shell without a locale, use `tmux -u`.

Each prompt shows user and host, the folder, the git branch with counts (`!` changed, `+` staged, `?` untracked), the time of a command that took over 2 seconds, and the exit code of a failed command.

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

# RDP

The `wsl` section installs only `/etc/wsl.conf`, and the menu ticks it by default on WSL (outside WSL it does nothing). hakpak's `wsl.conf` turns on systemd and turns off Windows drive automount (`/mnt/c`) and interop (running `.exe` files). If you already have a different `/etc/wsl.conf`, setup shows the difference (on a terminal, lines only in yours are red and only in hakpak's green; `NO_COLOR` turns all colors off), recommends one, and asks which to keep (`k` or `h`; Enter takes the recommendation). Replacing yours backs it up to `/etc/wsl.conf.bak` (or `.bak.<timestamp>` if that is taken), an identical file is never rewritten, and without a terminal yours is kept: set `HAKPAK_WSL_CONF=keep` or `replace` to decide up front. Run `wsl --shutdown` from Windows once after the install, then reopen WSL: xrdp (the `rdp` section) then starts with systemd. `startrdp` and `stoprdp` start and stop it by hand.

# Agent skills

`.claude/skills` holds skills for AI coding agents that test hakpak in a clean Linux box. Two cover [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/):

- `sbx-cli`: commands and flags of the `sbx` CLI, checked against `sbx --help` for v0.51.0.
- `sbx-arch`: how Docker Sandboxes works: isolation, network and credential model, limits, local versus cloud.

Neither was tested on a running sandbox; when one disagrees with `sbx COMMAND --help`, trust the help.

Two cover [WSL containers](https://learn.microsoft.com/windows/wsl/wsl-container), the `wslc.exe` runtime built into WSL on Windows:

- `wslc-cli`: commands, aliases and flags of the `wslc` CLI, taken from the microsoft/WSL source at release 3.0.5.
- `wslc-arch`: how WSL containers work: session VM, storage, networking, security model, enterprise policy, limits.

Neither was run against a live `wslc.exe`; when one disagrees with `wslc COMMAND --help`, trust the help.

Claude Code loads all four from a checkout of this repo, and the `top` section links every skill there into `~/.claude/skills` (or `$CLAUDE_CONFIG_DIR/skills`), so Claude Code has them in any project and `git pull` updates them. A skill of the same name that you already have is kept.

# Tests

```
bats tests
shellcheck -x install/*.sh tools/setup-router tools/gen-readme tools/hakpak-theme
```

The tests fail if the README tool list doesn't match `install/toolset.txt`; `tools/gen-readme` updates it.
