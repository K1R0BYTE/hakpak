# hakpak domain

**Toolset**: the full set of tools hakpak installs, grouped into sections. Listed once, one row per tool, in the manifest `install/toolset.txt`.

**Toolset manifest**: `install/toolset.txt`. Each row is `section kind name [source...]`, with an optional `# note` for the README. Section scripts install their rows with `install_section <id>`, and `tools/gen-readme` writes the README tool list from it.

**Section**: one group of the Toolset, installed by one script in `install/`: Top, Dev, AI, Network, Environment, Basic, Surfing, Web Tools, Pentest Tools, Cloud, CI/CD, MiTM, Wordlists, WSL config, RDP. The WSL config section (`wsl`) installs no tools, only `/etc/wsl.conf`; the menu ticks it on WSL, and it asks before replacing a different file.

**Setup**: `install/setup.sh [section...|all] [--dry-run]`. No sections opens the section menu: one checkbox per section and, in the section you open, one per tool from the manifest; ticking a section ticks its tools, and a tool in several sections is one checkbox (read key by key; it needs a terminal, otherwise setup asks for section names). `all` installs every section; named sections install all their tools, always in install order. Either way the **Install plan** (`toolset_plan`) gives each ticked tool to one section, and setup runs each section with its tools in `HAKPAK_TOOLS`. `--dry-run` turns on the Dry run. A failing section doesn't stop the next.

**Install plan**: which section installs each ticked tool: the ticked section with the largest share of its tools ticked, a tie going to the one installed first. A section whose ticked tools all come with others is not run. A ticked tool brings the tools it needs (`_toolset_needs`: Go for `go`, uv for `uv`, Claude Code and the marketplaces for `plugin`) when its section lists them, and they are installed no later than it. A section script installs only the tools in `HAKPAK_TOOLS` (all of them when it is unset) and puts in place only their configs (`tool_wanted`).

**Tool kind**: how a tool is installed. One of `apt`, `go`, `pipx`, `gem`, `git`, `venv`, `url`, `uv`, `plugin`, `custom`. A `uv` tool is a Python command line tool installed with `uv tool install`; a `plugin` is a Claude Code plugin, and its source is the marketplace it comes from. Every tool goes through `install_tool <kind> <name> …` in `install/lib.sh`. A `custom` tool names a function in `install/custom.sh`.

**Install module**: `install/lib.sh`. Knows how to install each tool kind, skips tools that are already present, keeps going when one tool fails, and prints the failed tools at the end, with the cause when their output shows one: a download the network refused (HTTP 403), or apt files that don't match its index (a stale mirror, which `apt_install` retries once after `apt-get clean` and `update`).

**Dry run**: `setup.sh --dry-run all` (or `--dry-run` with named sections, or `HAKPAK_DRY_RUN=1`) makes the install module record every command instead of running it (to `HAKPAK_DRY_RUN_LOG`, or stdout). Tests and CI use it; nothing is installed.

**Config**: a dotfile or system file kept in `configs/` and put in place on install by `link_config`: symlinked in your home, copied under `/etc`. A real file it replaces is backed up once to `<file>.bak`; re-runs are no-ops.

**Skills**: the agent skills kept in `.claude/skills`, one directory with a `SKILL.md` each. The Top section links each into `~/.claude/skills` (`_link_claude_skills`) when it installs Claude Code; a skill of the same name you already have is kept.

**AI section**: the Claude Code part of Dev on its own (`install/ai.sh`): Claude Code with the Skills, the plugin marketplaces and skill plugins, and Trail of Bits' claude-code-config. Dev keeps the same rows.

**Plugin marketplace**: a catalogue of Claude Code plugins. The Dev and AI sections register three (`trailofbits/skills`, `trailofbits/skills-curated`, `anthropics/skills`) and hakpak's own, `.claude-plugin/marketplace.json`, which lists a skill published as a plain repo as a plugin. Plugins install into `~/.claude/plugins`, so they also work where `~/.claude/skills` is read-only.

**Sandbox**: a Docker Sandbox (sbx), told by `$SANDBOX_NAME` and `/etc/sandbox-persistent.sh` (`is_sbx`). There the Dev section adds its environment (`system/.dev`) to that file (AI doesn't), a read-only `~/.claude/skills` is skipped by both, and an install the network policy refused (HTTP 403) names the `sbx policy` commands for the host.

**Theme**: a named look for the shell: a Starship prompt config `configs/starship/<name>.toml` and a tmux status bar `configs/tmux/themes/<name>.conf`. `tools/hakpak-theme <name>` picks one (`neon` by default); the choice is one word in `~/.config/hakpak/theme`, read by `.zshrc` and `.tmux.conf`, so the repo stays clean.

**History merge**: the curated `configs/zsh/.zsh_history` is added to your own history by `merge_history`, never linked, so new commands stay out of the repo.

**Repo root**: wherever hakpak is cloned. Scripts find it from their own path (`HAKPAK_ROOT`), not from a fixed `~/.hakpak`.
