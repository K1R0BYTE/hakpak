# hakpak domain

**Toolset**: the full set of tools hakpak installs, grouped into sections. Listed once, one row per tool, in the manifest `install/toolset.txt`.

**Toolset manifest**: `install/toolset.txt`. Each row is `section kind name [source...]`, with an optional `# note` for the README. Section scripts install their rows with `install_section <id>`, and `tools/gen-readme` writes the README tool list from it.

**Section**: one group of the Toolset, installed by one script in `install/`: System, Environment, Basic, Surfing, Web Tools, Pentest Tools, Cloud, CI/CD, MiTM, Wordlists, WSL config, RDP. The WSL config section (`wsl`) installs no tools, only `/etc/wsl.conf`; the menu ticks it on WSL, and it asks before replacing a different file.

**Setup**: `install/setup.sh [section...|all] [--dry-run]`. No sections opens the section menu (one checkbox per section with its tools from the manifest listed below it, or only under the cursor when the terminal is too short, read key by key; it needs a terminal, otherwise setup asks for section names); `all` installs every section; named sections install only those, always in install order. `--dry-run` turns on the Dry run. A failing section doesn't stop the next.

**Tool kind**: how a tool is installed. One of `apt`, `go`, `pipx`, `gem`, `git`, `venv`, `url`, `custom`. Every tool goes through `install_tool <kind> <name> …` in `install/lib.sh`. A `custom` tool names a function in `install/custom.sh`.

**Install module**: `install/lib.sh`. Knows how to install each tool kind, skips tools that are already present, keeps going when one tool fails, and prints the failed tools at the end.

**Dry run**: `setup.sh --dry-run all` (or `--dry-run` with named sections, or `HAKPAK_DRY_RUN=1`) makes the install module record every command instead of running it (to `HAKPAK_DRY_RUN_LOG`, or stdout). Tests and CI use it; nothing is installed.

**Config**: a dotfile or system file kept in `configs/` and put in place on install by `link_config`: symlinked in your home, copied under `/etc`. A real file it replaces is backed up once to `<file>.bak`; re-runs are no-ops.

**Theme**: a named look for the shell: a Starship prompt config `configs/starship/<name>.toml` and a tmux status bar `configs/tmux/themes/<name>.conf`. `tools/hakpak-theme <name>` picks one (`neon` by default); the choice is one word in `~/.config/hakpak/theme`, read by `.zshrc` and `.tmux.conf`, so the repo stays clean.

**History merge**: the curated `configs/zsh/.zsh_history` is added to your own history by `merge_history`, never linked, so new commands stay out of the repo.

**Repo root**: wherever hakpak is cloned. Scripts find it from their own path (`HAKPAK_ROOT`), not from a fixed `~/.hakpak`.
