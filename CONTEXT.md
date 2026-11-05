# hakpak domain

**Toolset**: the full set of tools hakpak installs, grouped into sections.

**Section**: one group of the Toolset, installed by one script in `install/`: System, Environment, Basic, Surfing, Web Tools, Pentest Tools, MiTM, Wordlists, WSL.

**Tool kind**: how a tool is installed. One of `apt`, `go`, `pipx`, `gem`, `git`, `venv`, `url`, `custom`. Every tool in a section script goes through `install_tool <kind> <name> …` in `install/lib.sh`.

**Install module**: `install/lib.sh`. Knows how to install each tool kind, skips tools that are already present, keeps going when one tool fails, and prints the failed tools at the end.

**Dry run**: `HAKPAK_DRY_RUN=1` makes the install module record every command instead of running it (to `HAKPAK_DRY_RUN_LOG`, or stdout). Tests and CI use it; nothing is installed.

**Config**: a dotfile or system file kept in `configs/` and put in place on install by `link_config`: symlinked in your home, copied under `/etc`. A real file it replaces is backed up once to `<file>.bak`; re-runs are no-ops.

**History merge**: the curated `configs/zsh/.zsh_history` is added to your own history by `merge_history`, never linked, so new commands stay out of the repo.

**Repo root**: wherever hakpak is cloned. Scripts find it from their own path (`HAKPAK_ROOT`), not from a fixed `~/.hakpak`.
