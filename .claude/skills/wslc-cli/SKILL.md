---
name: wslc-cli
description: Complete command and flag reference for `wslc.exe`, the WSL container CLI built into Windows Subsystem for Linux (also installed as `container.exe`), taken from the microsoft/WSL source at release 3.0.5. Use this whenever the user mentions wslc, wslc.exe, WSL containers, or wants to build, run, debug, script or clean up Linux containers on Windows without Docker Desktop, even if they only say "run this image on Windows", "port my docker commands to wslc", "the container can't see my C: drive", "publish a port from WSL" or "where does wslc keep its images". Covers every command in one place - run/create/exec/attach/logs/cp/stats/list/stop/kill/restart/remove/prune, image build/pull/push/save/load/import/tag, networks, volumes, registry login, inspect, events, sessions, settings.yaml, and the differences from the Docker CLI. Not for `wsl.exe` distro management, Docker Desktop, or the WSL container API (Microsoft.WSL.Containers).
---

# wslc: WSL container CLI

`wslc.exe` builds, runs and manages Linux containers on Windows. It ships inside WSL (no separate engine to install) and is also on PATH as `container.exe`, which behaves identically. The syntax follows the Docker CLI closely, but it is a different program with its own image store, a smaller flag set and a few different defaults.

For how WSL containers work inside (session VM, storage, networking, security model, limits) load `wslc-arch`.

This file was written from the command and flag definitions in the microsoft/WSL source at release **3.0.5** (October 2026). Nothing here was run against a live `wslc.exe`. The CLI is young and moves fast: older 2.9.x builds lack some of what is listed here (for example `restart`, `system info`, `events`, `network connect`, `--restart`, `--cap-add`). Treat this file as the map and the live help as ground truth. When a flag is rejected, or `wslc version` reports something other than 3.0.x, read `wslc COMMAND --help` before guessing. Help needs no running session, so it is always cheap.

## Before anything works

1. **WSL 2.9.3 or later.** `wsl --version` shows it; `wsl --update` upgrades. `wslc version` prints `wslc <version>` (`--format json` gives `{"Client":{"Version":...}}`), and `wslc --version` / `-v` does the same.
2. **A Windows shell.** Run it from PowerShell, cmd or Windows Terminal. It is a Windows program; from inside a WSL distro call it as `wslc.exe`.
3. **No daemon to start.** Containers live in a *session*, a lightweight VM that starts on demand and is torn down after 30 idle seconds (`session.idleTimeout`). The first command after a pause pays a short boot delay.

Elevated and non-elevated terminals use **different default sessions** (`wslc-cli-admin-<username>` and `wslc-cli-<username>`), each with its own images, containers, volumes and networks. "My image disappeared" usually means the terminal changed privilege level. Stay non-elevated unless there is a reason, and check with `wslc system session list`.

`wslc system info` prints the client and session manager versions, the settings file path and the active sessions. Run it first when something is off.

### Command line conventions

- `wslc [--session NAME] COMMAND [options] [args]`. `--session` is the only global option and goes before or after the subcommand.
- Help is `--help` or `-?` on any command. `-h` is **not** help; on `run` and `create` it is `--hostname`.
- Values attach with a space or `=` (`--name web`, `--name=web`, `-m 512M`, `-m=512M`). Short flags combine (`-it`, `-dit`); a short option that takes a value must be last in the group.
- Boolean flags accept `=false` (`--rm=false`). A repeated single-value option is last-wins; repeatable options accumulate.
- For commands that forward arguments (`run`, `create`, `exec`, `session run`), everything after the first positional belongs to the container command, so put wslc options **before** the image or container name.
- Color is disabled by setting the `NO_COLOR` environment variable. There is no `--no-color` flag.
- Exit code is 0 on success and 1 on a wslc error (bad arguments print the relevant help). `run`, `exec`, `attach` and `start --attach` return the container process's own exit code. Declining a confirmation prompt exits 0 without doing anything. Ctrl-C exits 1.

## Command map

Docker-style top-level shortcuts exist for most container and image commands; they are the same commands as the grouped forms.

| Group | Subcommands | Top-level shortcut |
|---|---|---|
| `container` | `attach` `cp` `create` `exec` `export` `inspect` `kill` `logs` `list` (`ls`, `ps`) `prune` `remove` (`rm`, `delete`) `restart` `run` `start` `stats` `stop` | all except `inspect` and `prune`: `wslc run`, `wslc exec`, `wslc list`/`ls`/`ps`, `wslc remove`/`rm`/`delete`, ... |
| `image` | `build` `import` `inspect` `list` (`ls`) `load` `prune` `pull` `push` `remove` (`rm`, `delete`) `save` `tag` | `build` `import` `load` `pull` `push` `save` `tag`, plus `wslc images` and `wslc rmi` |
| `network` | `connect` `create` `disconnect` `inspect` `list` (`ls`) `prune` `remove` (`rm`, `delete`) | none |
| `volume` | `create` `inspect` `list` (`ls`) `prune` `remove` (`rm`, `delete`) | none |
| `registry` | `login` `logout` | `wslc login`, `wslc logout` |
| `system` | `events` `info` `session` | `wslc events`, `wslc info` |
| `system session` | `enter` `list` `run` `shell` `terminate` | none |
| `settings` | (opens the file) `reset` | - |
| root | `inspect` (any object type) `version` | - |

Things that look like they should exist but do not: top-level `wslc prune`, `system prune`, `system df`, `pause`, `unpause`, `top`, `wait`, `port`, `rename`, `diff`, `commit`, `update`, `image history`, `search`, and any Compose, Swarm or buildx/bake command.

## Containers

### run and create

```
wslc run    [options] IMAGE [COMMAND] [ARG...]
wslc create [options] IMAGE [COMMAND] [ARG...]
```

`run` creates and starts a container in the foreground; `create` only creates it (start with `wslc start`). They take the same options, except `-d/--detach` exists only on `run`. A missing image is pulled automatically.

| Option | Notes |
|---|---|
| `-d, --detach` | Run in the background and print the container ID. `run` only. |
| `-i, --interactive` / `-t, --tty` | Keep stdin open / allocate a TTY. Usually `-it`. |
| `--name NAME` | Container name; also its DNS name on a user-defined network. |
| `--rm` | Remove the container when it stops. Cannot be combined with `--restart always`. |
| `-p, --publish SPEC` | `[HOST_IP:][HOST_PORT:]CONTAINER_PORT[/tcp\|udp]`, ranges like `8000-8005:8000-8005` (host range must match). Repeatable. Without `HOST_IP` it binds `127.0.0.1` (change with `session.defaultBindingAddress`). |
| `-P, --publish-all` | Publish every exposed port to a random host port. |
| `-v, --volume SPEC` | `[HOST_PATH\|VOLUME_NAME:]CONTAINER_PATH[:MODE]`. Repeatable. See "Host paths". |
| `--mount SPEC` | Docker `--mount` syntax (`type=bind,src=...,dst=...,readonly`). Repeatable. |
| `--tmpfs PATH` | tmpfs mount. Repeatable. |
| `-e, --env KEY=VALUE` / `--env-file FILE` | Environment variables. Repeatable. |
| `-w, --workdir DIR` | Working directory in the container. |
| `-u, --user USER` | `name`, `uid` or `uid:gid`. |
| `--entrypoint EXE` | Override the image entrypoint. |
| `-h, --hostname NAME` / `--domainname NAME` | Host and domain name. |
| `--network NAME` | `bridge`, `none`, `container:NAME`, or a user-defined network. Repeatable. `host` is rejected: "host mode networking is not supported". |
| `--network-alias ALIAS` / `--ip ADDR` | Alias and fixed IPv4 on a user-defined network (both require `--network`). |
| `--dns IP` / `--dns-option OPT` / `--dns-search DOMAIN` | resolv.conf settings. Repeatable. |
| `-m, --memory SIZE` | `512M`, `1G`. Suffixes are b, k, m, g, t with optional `b`/`ib`. 2.9.x rejected lowercase, so write uppercase. |
| `--cpus N` | Fractional CPUs, `0.5`, `2.5`. Must be above 0. |
| `--shm-size SIZE` | Size of `/dev/shm`. |
| `--ulimit NAME=SOFT[:HARD]` | `-1` for unlimited. Repeatable. |
| `--gpus all` | Pass all GPUs. `all` is the only accepted value. There is no `--device`. |
| `--cap-add CAP` / `--cap-drop CAP` | Linux capabilities. Repeatable. |
| `--restart POLICY` | Only `no` and `always`. `on-failure` and `unless-stopped` are rejected as unsupported. |
| `--pull always\|missing\|never` | Default `missing`. |
| `--stop-signal SIGNAL` / `--stop-timeout SECONDS` | `-1` means wait forever. |
| `--health-cmd CMD`, `--health-interval`, `--health-timeout`, `--health-start-period` (durations like `30s`, `1m30s`), `--health-retries N`, `--no-healthcheck` | `--no-healthcheck` cannot be combined with the others. |
| `-l, --label KEY=VALUE` | Repeatable. |
| `--cidfile PATH` | Write the container ID to a file. |

Not available: `--platform`, `--privileged`, `--security-opt`, `--device`, `--add-host`, `--pid`, `--ipc`, `--init`, `--read-only`, `--link`, `--expose`, `--memory-swap`, `--detach-keys`.

```powershell
wslc run --rm alpine echo ok                                   # smoke test
wslc run --rm -it ubuntu:latest bash                           # interactive shell
wslc run -d --rm -p 8080:80 --name web nginx                   # background web server on 127.0.0.1:8080
wslc run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi      # GPU
```

### Host paths

Bind mounts take Windows paths. Write them with forward slashes (`C:/work:/app`); a drive-letter colon is understood, but backslashes are easy to get wrong inside quoted strings. In PowerShell the current directory is:

```powershell
wslc run --rm -it -v "$($PWD.Path -replace '\\','/'):/app" -w /app node:22 bash
```

Host files are shared over VirtioFS. A bare name on the left of `-v` (`pgdata:/var/lib/postgresql/data`) is a named volume inside the session, not a host folder, and is the faster choice for databases and dependency caches.

### exec, attach, start, stop, kill, restart

| Command | Options |
|---|---|
| `wslc exec [options] CONTAINER COMMAND [ARG...]` | `-d`, `-i`, `-t`, `-u/--user`, `-w/--workdir`, `-e/--env`, `--env-file`. The container must be running. Returns the command's exit code. |
| `wslc attach CONTAINER` | Attach to the container's main process. |
| `wslc start CONTAINER` | `-a/--attach` attaches stdout/stderr. `-i/--interactive` is accepted but not implemented. One container per call. |
| `wslc stop CONTAINER...` | `-s/--signal` (default: the image's STOPSIGNAL, else SIGTERM), `-t/--time SECONDS` before the kill (default: the container's configured stop timeout). |
| `wslc kill CONTAINER...` | `-s/--signal` (default SIGKILL). |
| `wslc restart CONTAINER...` | `-s/--signal`, `-t/--timeout SECONDS`. Containers that are not running are started. |

Signals are names with or without `SIG` (`TERM`, `SIGHUP`) or numbers.

### list, logs, stats, inspect

```
wslc list [options]          # aliases: ls, ps
```

`-a/--all` includes stopped containers (default is running only), `-f/--filter KEY=VALUE` (repeatable), `--format json|table`, `-n/--last N`, `-l/--latest` (not together with `--last`), `--no-trunc`, `-q/--quiet` (IDs only), `-s/--size`.

```
wslc logs [options] CONTAINER
```

`-f/--follow`, `-n/--tail N` (N above 0), `-t/--timestamps`, `--since TS`, `--until TS` (Unix seconds or RFC 3339 such as `2026-01-15T10:30:00Z`), `--details`.

`wslc stats [CONTAINER...]` prints **one snapshot** (CPU, memory, network I/O, block I/O, PIDs) and returns; it never streams, so there is no `--no-stream`. `-a/--all`, `--format json|table`, `--no-trunc`.

`wslc container inspect CONTAINER...` takes `-s/--size` and `-f/--format json`. For every inspect command the default output is indented JSON and `--format json` only switches to single-line JSON; **Go templates are not supported**, so pipe to `ConvertFrom-Json` or `jq`. The top-level `wslc inspect OBJECT...` works on any object and takes `-t/--type image|container|network|volume`.

### cp and export

```
wslc cp [options] SRC DEST        # also: wslc container cp
```

One side is `CONTAINER:PATH`, the other a local Windows path. `SRC` may be `-` to read a tar archive from stdin (`tar -cf - files | wslc cp - web:/data`). `-L/--follow-link` follows symlinks in the source, `-q/--quiet` hides progress, `-a/--archive` is accepted for Docker compatibility. Local copies rely on Windows `tar.exe`. To copy a directory out, give a destination that ends in a path separator.

`wslc export CONTAINER -o FILE.tar` writes the container filesystem as a tar archive (stdout without `-o`, so redirect it).

### remove and prune

- `wslc remove CONTAINER...` (aliases `rm`, `delete`): `-f/--force` removes running containers, `-v/--volumes` also removes their anonymous volumes.
- `wslc container prune`: removes **all stopped containers**. `--filter until=TIMESTAMP` narrows it, `-f/--force` skips the confirmation.

## Images

### build

```
wslc build [options] PATH        # also: wslc image build
```

`PATH` is the build context directory, or `-` to read a tar archive or Dockerfile from stdin. The Dockerfile may be named `Dockerfile` or `Containerfile`.

| Option | Notes |
|---|---|
| `-t, --tag NAME[:TAG]` | Repeatable. |
| `-f, --file PATH` | Dockerfile path, `-` for stdin (not when the context is also stdin). |
| `--build-arg KEY=VALUE` | Repeatable. |
| `--target STAGE` | Multi-stage target. |
| `--no-cache` / `--pull` | Skip the cache / always try to pull newer base images. `--pull` is a plain flag here. |
| `-l, --label KEY=VALUE` | Repeatable. |
| `--secret id=NAME[,type=env\|file][,env=VAR\|,src=PATH]` | Defaults to the host environment variable named like the id, which must be set. Repeatable. |
| `-o, --output SPEC` | buildx-style, for example `type=tar,dest=out.tar`, `type=oci,dest=image.tar`, `type=docker,dest=image.tar`. Directory exporters (`type=local`) are not supported. |
| `--progress auto\|tty\|plain\|quiet` | Default `auto`. Use `plain` in CI logs. |
| `--iidfile PATH` | Write the image ID to a file. |
| `--verbose` | Detailed output. |

No `--platform` (host architecture only), `--ssh`, `--cache-from`/`--cache-to` or `--push`. Save a Dockerfile written from PowerShell 5.1 without a BOM, or the build can fail on the first instruction.

### Other image commands

| Command | Options and notes |
|---|---|
| `wslc pull IMAGE` | `-a/--all-tags`, `-q/--quiet`. No tag means `latest`. |
| `wslc push IMAGE` | `-a/--all-tags`, `-q/--quiet`. Log in first for private registries. |
| `wslc images` / `wslc image list` | `-a/--all` (show intermediate images), `--digests`, `-f/--filter` (repeatable), `--format json\|table`, `--no-trunc`, `-q/--quiet`, `--verbose`. |
| `wslc tag SOURCE TARGET` | Both in `name[:tag]` form. |
| `wslc save IMAGE... -o FILE.tar` | Write images to a tar archive. |
| `wslc load -i FILE.tar` | `-q/--quiet`. Loads images saved by `save` or `docker save`. |
| `wslc import FILE [IMAGE]` | Create an image from a filesystem tarball; `FILE` may be `-` for stdin. `--no-trunc`. |
| `wslc image inspect IMAGE...` | `-f/--format json`. |
| `wslc rmi IMAGE...` / `wslc image remove` | `-f/--force` removes images that are in use, `--no-prune` keeps untagged parents. |
| `wslc image prune` | Removes dangling images; `-a/--all` removes every image not used by a container. `--filter until=TIMESTAMP`, `-f/--force`. |

Images are stored per session and are **not shared with Docker Desktop**. To move one across without a registry: `docker save myapp:dev -o myapp.tar` then `wslc load -i myapp.tar`.

## Registries

```
wslc login [-u USER] [-p PASSWORD | --password-stdin] [SERVER]
wslc logout [SERVER]
```

Without `SERVER` the session's default registry is used. Missing values are prompted for. `--password-stdin` requires `--username` and cannot be combined with `--password`; it is the form to use in scripts, because `-p` leaves the token in shell history:

```powershell
$env:GHCR_TOKEN | wslc login ghcr.io -u myuser --password-stdin
```

Credentials are kept in Windows Credential Manager per user (`credentialStore: wincred`, or `file`).

## Networks

Containers on the same user-defined network reach each other by container name. This is how a Compose stack is reproduced.

| Command | Options |
|---|---|
| `wslc network create NAME` | `-d/--driver` (default `bridge`), `-o/--opt KEY=VALUE`, `-l/--label`, `--subnet CIDR`, `--gateway IP` and `--ip-range CIDR` (both need `--subnet`), `--internal` (no external access), `--ipv6`. |
| `wslc network connect NETWORK CONTAINER` | `--ip ADDR`, `--network-alias ALIAS`, `--link NAME:ALIAS`, `--link-local-ip ADDR`, `--driver-opt KEY=VALUE`. |
| `wslc network disconnect NETWORK CONTAINER` | - |
| `wslc network list` (`ls`) | `-f/--filter`, `--format json\|table`, `--no-trunc`, `-q/--quiet` (IDs only). |
| `wslc network inspect NETWORK...` | `-f/--format json`. |
| `wslc network remove NETWORK...` (`rm`, `delete`) | `-f/--force` only suppresses the error for a missing network. |
| `wslc network prune` | Removes networks no container references. `--filter`, `-f/--force`. |

From inside a container, the Windows host is reachable as `host.wslc.internal` (`session.hostLoopback`). Windows VPN and proxy settings apply to container traffic without extra setup.

## Volumes

| Command | Options |
|---|---|
| `wslc volume create [NAME]` | `-d/--driver guest\|vhd` (default `guest`), `-o/--opt KEY=VALUE`, `-l/--label`. Without a name one is generated. |
| `wslc volume list` (`ls`) | `-f/--filter`, `--format json\|table`, `-q/--quiet` (names only). |
| `wslc volume inspect VOLUME...` | `-f/--format json`. |
| `wslc volume remove VOLUME...` (`rm`, `delete`) | Fails while a container uses the volume. `-f/--force` only suppresses the error for a missing volume. |
| `wslc volume prune` | Removes unused **anonymous** volumes; `-a/--all` also removes unused named volumes. `--filter label=LABEL`, `-f/--force`. |

## Sessions and system

A session is the VM that holds the engine, images, containers, volumes and networks. Normally the default one is all that is needed.

| Command | Purpose |
|---|---|
| `wslc system info [--format json\|table]` | Versions, settings file path, active sessions. |
| `wslc events [--since TS] [--until TS] [-f KEY=VALUE]... [--format json\|table]` | Stream container events until interrupted or `--until` is reached. |
| `wslc system session list [--verbose]` | Active sessions. |
| `wslc system session shell` | Open a shell inside the session VM (not a container). Useful for looking at the engine itself. |
| `wslc system session run COMMAND [ARG...]` | Run a command in the session VM without a TTY. |
| `wslc system session terminate` | Stop the session VM, which stops its running containers. Images, volumes and stopped containers stay on disk and the next command starts it again. |
| `wslc system session enter STORAGE_PATH [--name NAME]` | Create a temporary session with its own storage in an empty directory and open a shell in it; the session is deleted when the shell exits. Does not accept `--session`. |

`shell`, `run` and `terminate` act on the default session unless `--session NAME` is given.

## Settings

`wslc settings` opens `%LOCALAPPDATA%\wslc\settings.yaml` in the default editor, creating it on first use with every setting commented out. It opens a GUI editor, so from a script or an agent's shell edit the file directly. `wslc settings reset` overwrites the file with the defaults template. Unknown or invalid keys print a warning and fall back to the default. Any value may be the string `default`.

```yaml
session:
  cpuCount: 4                    # default: all CPUs
  memorySize: 8GB                # default: half of host memory
  maxStorageSize: 500GB          # default: 1TB
  storagePath: D:\data           # default: %LOCALAPPDATA%; VHD is <storagePath>\wslc\sessions\<session>\storage.vhdx
  defaultBindingAddress: 0.0.0.0 # default: 127.0.0.1, used by -p without a host IP
  hostLoopback: host.wslc.internal   # "none" disables the name
  idleTimeout: 30                # seconds before an idle session VM stops
  networkingMode: consomme       # consomme (default), nat, none
  hostFileShareMode: virtiofs    # virtiofs (default) or plan9
  dnsTunneling: true
credentialStore: wincred         # or file
```

Changing `storagePath` does **not** move existing data: a new empty session is created at the new path and the old images and containers stay behind at the old one. Apply session settings with `wslc system session terminate`, then run any command.

## Coming from Docker

| Docker habit | wslc |
|---|---|
| `docker compose up` | No Compose. Create a network, then one `wslc run --network` per service. |
| `docker system prune` | Prune per type: `container prune`, `image prune`, `volume prune`, `network prune`. |
| `docker inspect --format '{{...}}'` | No templates. Parse the JSON. |
| `docker stats` live view | One snapshot per call. |
| `--restart unless-stopped` | Only `no` and `always`. |
| `--network host` | Not supported. Publish ports, or use `host.wslc.internal` to reach the host. |
| `--platform linux/arm64` | Host architecture only. |
| `-p 8080:80` reachable from the LAN | Binds `127.0.0.1`. Use `-p 0.0.0.0:8080:80` or `defaultBindingAddress`. |
| `/var/run/docker.sock` mounts, Testcontainers | No Docker socket; socket-based tools do not attach. |
| `-h` for help | `-h` is `--hostname`. Help is `--help` or `-?`. |
| Windows containers | Linux images only. |

If Docker Desktop also publishes the same port it listens on `0.0.0.0` and `[::]`, and `localhost` may resolve to `::1` and reach Docker's container. Test wslc ports with `curl.exe http://127.0.0.1:PORT/`. Use `curl.exe`, since `curl` in Windows PowerShell 5.1 is an alias for `Invoke-WebRequest`.

## Recipes

**App plus database on one network**

```powershell
wslc network create appnet
wslc volume create pgdata
wslc run -d --name db --network appnet -v pgdata:/var/lib/postgresql/data -e POSTGRES_PASSWORD=dev `
  --health-cmd "pg_isready -U postgres" --health-interval 10s --health-retries 3 postgres:16-alpine
wslc build -t myapp:dev .
wslc run -d --name api --network appnet -p 3000:3000 -e DATABASE_URL=postgres://postgres:dev@db/postgres myapp:dev
wslc logs -f api
```

**Scripted run with a real exit code**

```powershell
wslc run --rm -v "C:/src/proj:/src" -w /src node:22 npm test
if ($LASTEXITCODE -ne 0) { throw "tests failed: $LASTEXITCODE" }
```

**Machine-readable listings**

```powershell
wslc list -a --format json | ConvertFrom-Json
wslc inspect web | ConvertFrom-Json | ForEach-Object { $_.State }
wslc list -aq                          # IDs only
```

**Tear down and reclaim space**

```powershell
wslc list -a                           # look before deleting
wslc remove -f api db
wslc network remove appnet
wslc container prune -f
wslc image prune -f                    # add -a to drop every unused image
wslc volume prune -f                   # add -a to include named volumes: this deletes data
```

## Reporting back

Prune commands and `remove -f` cannot be undone, and `volume prune --all` deletes database data. Show the user `wslc list -a` or `wslc volume list` and name what will go before deleting on their behalf; pass `-f` only once they agree, because the prompt cannot be answered from a non-interactive shell.

When you run wslc for the user, say which container names you started and whether they are still running, and mention the published address (`127.0.0.1:PORT`). If a command fails with an unknown option, check `wslc version` and the command's `--help` before retrying, and say which version you found, because the answer usually is that the installed WSL predates the feature.
