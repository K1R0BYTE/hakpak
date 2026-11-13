---
name: sbx-cli
description: Command and flag reference for the Docker Sandboxes `sbx` CLI (isolated microVM sandboxes for AI coding agents), checked against `sbx --help` for v0.51.0 with notes on what changed up to v0.53. Use this whenever the user mentions sbx, Docker Sandboxes, sandboxd, or wants to run claude/codex/gemini/copilot or a plain shell in a sandbox, or to script, automate, debug or clean up sandboxes, even if they only say "spin up a sandbox", "run this installer in a clean box", "the sandbox can't reach the network", "give the sandbox my token" or "copy the file out". Covers the whole CLI in one place - run/create/exec/cp/ls/stop/rm/prune/ports, network policy, secrets, MCP servers, templates, settings, daemon and diagnose, cloud sandboxes (--cloud, attach, move, ttl, volume), and the experimental env/kit/skills/setup commands. For how it works, limits and is-it-safe questions use sbx-arch. Not for `docker agent run --sandbox` or ordinary `docker run` containers.
---

# sbx: Docker Sandboxes CLI

`sbx` runs AI coding agents (or a plain shell) inside isolated sandboxes managed by a local daemon, `sandboxd`. This skill is a map of the whole CLI. For why something is blocked, what is safe, and limits, load `sbx-arch`.

## Scope, version and trust order

- Commands and flags come from the real `--help` output of **sbx v0.51.0**. Reasons, hidden commands and anything marked with a version come from docs.docker.com/ai/sandboxes, which describe up to **v0.53.0** (read 2026-11-13).
- Trust order: `sbx COMMAND --help` on the machine in front of you, then this file, then memory. The CLI is pre-1.0 and renames flags between releases, so check `sbx version` first and read the live help when a flag is rejected. Help works without signing in.
- Never invent a flag. If it is not here and not in help, say so.

## Mental model

- `sbx run AGENT [PATH]` creates a sandbox (a microVM) and attaches you to the agent. `sbx create` creates without attaching.
- Sandboxes persist until `sbx rm`. Stopping keeps packages, images and files.
- Most options are fixed at creation (workspace, `--clone`, `--publish` on run, `--skills`, kits, disk sizes). To change one, remove and recreate.
- Outbound network is controlled by policy on the host (`sbx policy`). Credentials live on the host (`sbx secret`) and a proxy injects them.
- The global `--cloud` flag targets Docker-managed cloud sandboxes, which have separate state, secrets and policy.

## Before anything works

Almost every command needs three things, and the error messages for a missing one look unrelated to the command you ran:

1. **Signed in.** `sbx login` (browser), or in CI `echo "$DOCKER_PAT" | sbx login --username me --password-stdin`. Without it commands fail with `error: not signed in to Docker` on stderr and exit 1 (`sbx exec` exits 125).
2. **Daemon running.** It starts on demand; manage it with `sbx daemon start [-d] [--policy allow-all|balanced|deny-all]`, `status`, `stop`, `restart`.
3. **Hardware virtualization.** Sandboxes are microVMs. On Linux that means `/dev/kvm`; inside a VM, container or CI runner without nested virtualization nothing can start.

When something is off, run `sbx diagnose` first. It checks the binary, daemon, virtualization, storage, auth and network policy in one report (`--format json|yaml|github-issue`, `--upload` sends it to Docker support).

### Install

| OS | Needs | Install |
|---|---|---|
| Ubuntu 24.04+ (x86-64 or Arm64) | KVM on, user in the `kvm` group | `curl -fsSL https://get.docker.com \| sudo REPO_ONLY=1 sh` then `sudo apt-get install docker-sbx` |
| macOS 14+ (Apple silicon) | nothing extra | `brew install docker/tap/sbx` |
| Windows 11 (x64) | Windows Hypervisor Platform enabled | `winget install -h Docker.sbx` |

Only the Ubuntu `apt-get install docker-sbx` step was run while writing this; the other lines are from the docs. Docker Desktop or Docker Engine is not required. On Linux, `sudo usermod -aG kvm $USER` and sign in again if `/dev/kvm` is not accessible.

### Global flags (go before or after the subcommand)

| Flag | Meaning |
|---|---|
| `--cloud` | Send the command to Docker Cloud Sandboxes instead of local `sandboxd`. Changes semantics of many commands, see "Cloud". |
| `--no-input` | Never prompt. A command that needs an answer fails and prints the command to run instead. Use it in every script. |
| `-D, --debug` | Debug logging. |

Most listing and mutating commands take `--format table|json|yaml` and `--json`; listings take `-q/--quiet` for names only. Destructive commands prompt unless `-f/--force`.

Running `sbx` with no command opens interactive mode; `sbx tui` opens the dashboard. Neither is useful from a script or an agent's shell.

## Core lifecycle

### Agents

Built in: `claude`, `codex`, `copilot`, `cursor`, `devin`, `docker-agent`, `droid`, `gemini`, `kiro`, `opencode`, `shell`. Use `shell` when the user wants a clean Linux box and no agent (for example to test an installer). The agent position also accepts a sandbox kit reference: a local directory, ZIP, git repository or OCI reference. Relative local kits must be written as explicit paths (`./my-kit`), because a bare word is read as an agent or sandbox name.

### run: create if needed, then attach

```
sbx run [flags] [AGENT|SANDBOX_KIT] [PATH...] [-- AGENT_ARGS...]
```

- No PATH mounts the **current directory**. The workspace appears inside the sandbox at the same absolute path as on the host.
- Extra workspaces are `PATH[:TARGET][:ro]`. `TARGET` is an absolute path inside the sandbox. `:ro` makes it read-only, and a read-only argument may be a single file, which is how you protect one file inside an otherwise writable workspace.
- Everything after `--` goes to the agent: `sbx run claude -- --continue`.
- Default name is `<agent>-<workdir>`. Set one with `--name` (two or more characters, starting with a letter or digit; letters, digits, hyphens and periods, no periods with `--cloud`; `default` is reserved).
- **Reattach** with `sbx run --name NAME`. The agent is read from the sandbox, so it can be omitted; giving it verifies it matches.
- `-d/--detach` starts the sandbox and prints its ID without opening a session. This is the form to use from scripts and from an agent's own shell, followed by `sbx exec`.
- `--rm` removes the sandbox when the session exits.
- `-w/--workdir` sets where this session starts (absolute, or relative to the workspace); it works on reattach.

```bash
sbx run claude                                  # current directory
sbx run claude . ~/docs:ro ~/data:/workspace/data
sbx run --name scratch -d shell .               # background, no session
sbx run --name scratch                          # reattach later
```

### create: never attaches

```
sbx create AGENT|SANDBOX_KIT [PATH...] [flags]
```

The difference from `run` that catches people: with `create`, **omitting PATH means no workspace bind mount at all** (the agent works in the container's own filesystem), whereas `run` with no PATH mounts the current directory. Pass `.` explicitly when you want the current directory. Attach afterwards with `sbx run --name NAME`.

`create` takes the flags in the table below but not `-d/--detach`, `--rm` or `-w/--workdir`; those belong to `run` and fail with `unknown flag` on `create`.

### Flags shared by run and create

| Flag | Notes |
|---|---|
| `--clone` | Agent works on a private in-container clone of the host Git repo (host repo mounted read-only). Its commits are reachable on the host through the git remote `sandbox-<name>`. Creation time only; see "Clone mode" below for its preconditions and how not to lose commits. |
| `-e, --env KEY=VALUE` / `--env-file FILE` | A bare `KEY` copies the value from the current environment. `--env` wins over files, later files win over earlier. On `run` they also apply to a reattached session. |
| `-p, --publish SPEC` | `[[HOST_IP:]HOST_PORT:]SANDBOX_PORT[/PROTOCOL]`. Applied at creation only and **ignored on reattach**; use `sbx ports` afterwards. |
| `--cpus N` | `0` means auto (all host CPUs). |
| `-m, --memory SIZE` | Binary units (`512m`, `8g`). Minimum 512 MiB. Default is half of host memory, clamped to 512 MiB to 32 GiB. |
| `-t, --template IMAGE` | Container image to use in place of the agent default. |
| `--pull always\|missing\|never` | Use `never` with locally saved templates. |
| `--deny-network PATTERN` | Per-sandbox deny rule added at creation. Repeatable. |
| `--static-mcp NAMES` | Fixed MCP server set, chosen once at creation (`notion,atlassian`, repeated flags, or `none`). Names come from `sbx mcp add`. |
| `--skills off\|readonly\|readwrite` | How the shared skills store is exposed in the agent's skills directory. Default `readonly`. Creation only. |
| `--profile NAME` | Governance profile (see `sbx policy profile ls`). |
| `--kit REF`, `--kit-arg name=value`, `--kit-args-file FILE`, `--mount HOST:SANDBOX_PATH` | Experimental kit mixins and their arguments and host mounts. Creation only. |
| `--no-progress` | Quieter output for logs. |

Cloud-only flags on both: `--allow-network`, `--ttl`, `--on-timeout stop|restart|delete`, `--platform`, `--image-ref`, `-v/--volume NAME:MOUNTPATH`. On `run` only: `--new`, `--detach-keys`.

`:ro` on a workspace blocks writes, not reads. The agent can still read every file under it, so do not mount a secrets file into a sandbox in any mode.

### Clone mode

`--clone` protects the host checkout from writes. It does not hide anything: the whole Git root, including untracked and ignored files such as `.env`, is readable inside the sandbox.

- Preconditions, checked at creation: an explicit PATH, inside a Git repository, that is not a linked worktree, and whose `.git` is a real directory. (These four are not in help; they match messages in the binary.)
- Passing `--clone` when reattaching is a no-op on a sandbox created in clone mode, and an error on one that was not. Recreate to switch modes.
- **Unfetched commits are deleted with the sandbox.** Before `sbx rm` or `sbx prune`, run `git fetch sandbox-<name>` on the host. `rm` and `prune` print a warning for clone-mode sandboxes; read it instead of passing `--force` by habit.
- If a sandbox was removed after a fetch, its branches survive on the host under `refs/sandboxes/<name>/*`. Recover one with `git branch <local-name> refs/sandboxes/<name>/<branch>`. (From Docker's own skill; not verified on a running sandbox.)

### Hidden but real

These do not appear in `sbx --help` on v0.51.0, but the binary accepts them:

| Command or flag | Use |
|---|---|
| `sbx inspect SANDBOX [--json]` | One sandbox in detail: agent, kits, state, workspace and mounts, policy, secrets, ports, sessions. With `--cloud`, also the URL of each published port. |
| `sbx events [TYPE...] [--json]` | Stream daemon events until Ctrl-C. `sandbox.lifecycle` filters by prefix. |
| `sbx policy approval ls`, `inspect ID`, `respond ID --option OPTION-ID` | Review requests that policy blocked and queued. |
| `sbx --cloud schedule ...` | Start cloud sandboxes on a cron cadence. Read `sbx schedule --help` for the subcommands. |
| `sbx run --model`, `--provider`, `--variant`, `--branch`, `--gpu`, `--usb` | Accepted by `run`; their semantics were not checked. `create` rejects `--model` and `--provider`. |

### exec: run a command in a sandbox

```
sbx exec [flags] SANDBOX COMMAND [ARG...]
```

Flags mirror `docker exec`: `-i`, `-t`, `-u/--user`, `-w/--workdir`, `-e/--env`, `--env-file`, `--privileged`. A stopped sandbox is started first. `-d/--detach` is listed but **not supported**; to background something, do it inside the command (`sbx exec NAME sh -c 'nohup ... &'`).

Exit status is the command's own. `125` means sbx could not run it at all (for example the sandbox does not exist) and `127` means the command was not found, so scripts can tell "my command failed" from "sbx failed".

```bash
sbx exec -it my-sandbox bash                 # interactive shell
sbx exec -u root my-sandbox apt-get update   # as root
sbx exec -w /srv my-sandbox ./install.sh     # non-interactive, propagates exit code
```

Commands run as the sandbox's unprivileged user by default (check with `sbx exec NAME whoami`; in the agent images it is normally `agent`). Reach for `-u root` when a step needs root. The docs give `/home/agent/workspace` as the working directory for sandboxes without a mounted workspace; pass `-w` when a script depends on where it starts.

### cp

```
sbx cp SRC DST          # one side is SANDBOX:PATH, the other a local path
```

Sandbox to sandbox is not supported. Copying a directory places the directory itself at the destination: created if the destination is missing, placed inside it if the destination is an existing directory. `-L/--follow-link` follows symlinks in the source. Symlinks that escape a mounted workspace are refused even with `-L`.

### ls, stop, rm, prune

| Command | Notes |
|---|---|
| `sbx ls` (alias `list`) | Agent, status, published ports, workspace. `-q` for names, `--format json` for scripts. |
| `sbx stop SANDBOX...` | Keeps state. Restart with `sbx run --name NAME` (or any `sbx exec`). |
| `sbx rm [SANDBOX...]` (aliases `remove`, `delete`) | Stops, deletes the container and sandbox state, cleans up Git worktrees and **deletes secrets scoped to that sandbox**. For a `--clone` sandbox, fetch its commits first. `--all` removes every sandbox. Irreversible. |
| `sbx prune` | Removes only **stopped** sandboxes, never running ones. `--dry-run` previews, `--filter until=168h` (or RFC 3339 / Unix timestamp) limits to sandboxes stopped before that point. Local only. |

Anything that deletes prompts for confirmation: `rm`, `prune`, `reset`, `logout`, `policy reset`, `policy rm network`, `secret rm`, `template rm`, `mcp rm`, `mcp auth rm`, `env rm`, `skills rm`, `kit builder rm`, and `move`. Under `--no-input` these fail unless given `-f/--force`. On `rm` and `prune`, `--force` also removes sandboxes that are in use, so name the targets explicitly and show the user `sbx prune --dry-run` or `sbx ls` before deleting on their behalf.

### ports

```
sbx ports SANDBOX [--publish SPEC]... [--unpublish SPEC]...
```

With no flag it lists. Publish spec is `[[HOST_IP:]HOST_PORT:]SANDBOX_PORT[/PROTOCOL]`; unpublish needs the host port, `[HOST_IP:]HOST_PORT:SANDBOX_PORT[/PROTOCOL]`. Protocols are `tcp`, `tcp4`, `tcp6`, `udp`, `udp4`, `udp6`.

- No `HOST_PORT` allocates an ephemeral one, so read it back with `sbx ports NAME`.
- No `HOST_IP` binds loopback only.
- No protocol means **tcp4** (127.0.0.1 only; tcp6 when HOST_IP is IPv6). If a client connects to `localhost` and resolves `::1`, publish `/tcp` explicitly to bind both families.
- Publishing starts a stopped sandbox. Re-check bindings with `sbx ports NAME` after a restart.

## Network policy

Egress is controlled by a global policy plus optional per-sandbox rules. Symptoms of a policy block are ordinary network errors inside the sandbox (timeouts, connection refused, TLS failures from `curl`, `apt`, `npm`, `git`), so check policy before debugging the tool.

**Debugging loop:**

```bash
sbx policy log my-sandbox --limit 20            # what was allowed or blocked, and by which rule
sbx policy check network --sandbox my-sandbox registry.npmjs.org   # would this be allowed? Read-only, no request made.
                                                # Without --sandbox only the global policy is evaluated.
sbx policy check http --method POST https://api.example.com/v1/items
sbx policy allow network --sandbox my-sandbox "registry.npmjs.org,*.githubusercontent.com"
```

Read the PROXY column of `sbx policy log`. It tells you which path the request took, and only one path can add credentials:

| PROXY | Meaning |
|---|---|
| `forward` | Forward proxy. Credential injection works. |
| `forward-bypass` | Forward proxy without TLS termination. No injection. |
| `transparent` | Client ignored the proxy settings (common inside nested containers). Policy enforced, **no injection**, so API calls fail with auth errors although the secret is set. |
| `network` | Non-HTTP traffic. |
| `browser-open` | The sandbox asked the host browser to open a URL. |

**Commands:**

| Command | Purpose |
|---|---|
| `sbx policy init allow-all\|balanced\|deny-all` | One-time global setup. `balanced` allows typical development traffic (AI services, package registries) and is the recommended start. It is a one-time setup; `sbx policy reset` clears everything to start over. |
| `sbx policy allow network [--sandbox S] RESOURCES` | Add an allow rule. Global unless `--sandbox`. |
| `sbx policy deny network [--sandbox S] RESOURCES` | Add a deny rule. |
| `sbx policy rm network [--id RULE_ID] [--resource HOSTS] [--sandbox S] [-f]` | Remove a rule by ID, resource, or both. `--id` takes the RULE_ID, not the rule name. |
| `sbx policy ls [SANDBOX]` | Overview. `--wide` shows rule IDs and resources. Filters: `--type network\|http\|filesystem`, `--source local\|org\|kit`, `--decision allow\|deny`, `--created-via`, `--profile`, `--include-inactive`. |
| `sbx policy inspect POLICY\|RULE` | Full detail, including the exact removal command or why a rule is read-only. |
| `sbx policy check network\|http ...` | Evaluate without making a request. `--verbose` shows the matched action. |
| `sbx policy log [SANDBOX]` | Allowed and blocked hosts with matching rule. `--limit N`, `--json`. |
| `sbx policy refresh` | Fetch organization governance policy now. Applies to new connections only. |
| `sbx policy profile ls` | Governance profiles usable with `--profile`. |
| `sbx policy approval ls\|inspect\|respond` | Hidden on v0.51.0. Under `balanced` or `deny-all` an unmatched request is blocked and queued; approving covers one destination and port for one sandbox and only helps later requests, so rerun the operation. |
| `sbx policy reset` | Deletes the local policy store and **stops the daemon, which stops running sandboxes**. |

**Rules worth knowing:**

- `RESOURCES` is one comma-separated argument: exact hosts (`example.com`), `*.example.com` (one label), `**.example.com` (any depth), IPs, CIDRs, optional port (`example.com:443`). `**` means everything; a bare `*` is rejected. Quote globs so the shell does not expand them.
- **Deny beats allow**, including across scopes: a per-sandbox deny overrides a global allow.
- Adding a rule that contradicts an existing rule in the *same* scope is refused. Remove the old rule first.
- Allow rules default to TCP; deny rules default to TCP and UDP. `--protocol tcp|udp` selects.
- `--method GET,HEAD --path '/v1/**' --query name=value` turns a rule into an HTTP-level rule.
- Organization rules (`--source org`) cannot be edited locally. A local deny can still narrow them. When `sbx policy ls` starts with `Governance: Managed by <org>`, local and kit allow rules are inactive; confirm with `sbx policy ls --wide --include-inactive` and ask the admin.
- `Governance: Unresolved` (or a stale policy snapshot) blocks every request. Check the network, run `sbx login` again, then contact the org admin.
- `example.com` and `*.example.com` do not cover each other. List both when you need the apex and its subdomains.
- `sbx policy check` reports the host-level decision. A host can show as allowed while a method or path rule denies the real request, so test HTTP rules with a real request from inside.
- From inside a sandbox, reach a service on the host as `host.docker.internal:PORT`, and allow it as `localhost:PORT`. `127.0.0.1` and the LAN IP do not work.
- ICMP is always blocked, so `ping` cannot be made to work. UDP is off unless an experimental feature is enabled (see `sbx-arch`).

## Secrets

The design goal is that real credentials never enter the sandbox: the host-side proxy injects them into outbound requests. Prefer this over passing tokens with `-e`, which puts the raw value inside the sandbox where the agent and anything it runs can read it.

**Service secrets.** Services: `anthropic`, `copilot`, `cursor`, `devin`, `droid`, `github`, `google`, `groq`, `mistral`, `nebius`, `openai`, `openrouter`, `xai`.

```bash
sbx secret set github                              # interactive prompt
echo "$ANTHROPIC_API_KEY" | sbx secret set anthropic   # stdin, safe for scripts
sbx secret set openai --sandbox my-sandbox         # one sandbox only (default is global)
sbx secret set github --command 'gh auth token'    # resolved on the host when needed
sbx secret set anthropic --ref 'op://Private/Anthropic/api-key'   # 1Password or AWS Secrets Manager ARN
sbx secret set openai --oauth                      # OAuth flow
sbx secret import [SERVICE] [--all] [--dry-run]    # pull from host env vars like GH_TOKEN
```

`-t/--token VALUE` exists but lands in shell history and the process list; use stdin. `--command` helpers run on the host from a temporary directory, so give absolute paths and keep the helper outside any directory mounted into a sandbox, otherwise the agent could rewrite what runs on the host. `--refresh` sets the cache policy (default 55m, or `on-demand`).

**Registry credentials** (for pulling private templates and kits) are host-only by default and are not injected into sandboxes:

```bash
gh auth token | sbx secret set --registry ghcr.io --password-stdin
# add --all-sandboxes or --sandbox NAME to also inject into sandboxes; --username for non-token auth
```

**Custom secrets (experimental)** for services sbx does not know. The sandbox sees a placeholder; the proxy swaps in the real value on requests to the named hosts:

```bash
printf '%s' "$API_KEY" | sbx secret set-custom --host api.example.com --env API_KEY --value-stdin
```

`--host` is repeatable and accepts wildcards. `--placeholder 'sk-{rand}'` shapes the placeholder for tools that validate key format.

**List and remove:** `sbx secret ls [-g] [--sandbox S] [--service X]`; `sbx secret rm [SERVICE] [--sandbox S]`, `--registry HOST`, `--placeholder VALUE`, or `--all` for everything. If a service already has an OAuth token, an imported API key is ignored until you `sbx secret rm SERVICE`.

## MCP servers

Register once on the host, then attach to sandboxes.

```bash
sbx mcp add notion --url https://mcp.notion.com/mcp                        # remote, OAuth discovered
sbx mcp add github --command npx --args @modelcontextprotocol/server-github  # local stdio
sbx mcp load notion --sandbox my-sandbox      # attach to a sandbox; tools appear without agent restart
sbx mcp unload notion --sandbox my-sandbox
sbx run claude --static-mcp notion,github     # or fix the set at creation
```

`--command` servers run **on the host with the user's full permissions**, not in the sandbox, so only register executables the user trusts. `--url` also accepts community-registry URLs, server manifest URLs and `dhi.io/...` image references. Other `add` flags cover custom headers with secret placeholders (`--header 'Authorization: Bearer ${api-key}'` plus `sbx secret set mcp:NAME:api-key`), OAuth tuning (`--client-id`, `--scope`, `--no-scope`, `--resource`, `--oauth-authorization-server`, `--callback-port`, `--skip-auth`) and `--skip-ssrf-check` for private-network endpoints.

Also: `sbx mcp ls`, `sbx mcp inspect NAME`, `sbx mcp rm NAME [--registration-only]`, and OAuth management with `sbx mcp auth [SERVER|--all]`, `sbx mcp auth status`, `sbx mcp auth rm`.

## Templates

A template is a saved snapshot of a sandbox, used to start new ones with tools preinstalled.

```bash
sbx template save my-sandbox myimage:v1.0 [--output /tmp/myimage.tar]
sbx run --pull never -t myimage:v1.0 claude ./project    # never is already the default for local snapshots; explicit is safer
sbx template load /tmp/myimage.tar                       # on another host
sbx template ls
sbx template rm myimage:v1.0
```

`sbx template inspect` is cloud-only.

## Settings, daemon, reset

- `sbx settings ls [--no-trunc]`, `get KEY`, `set KEY VALUE`, `unset KEY`. Environment variables beat user overrides. Examples from the help: `sbx settings set proxy http://proxy.example.com:3128` (upstream proxy for sandbox, daemon and CLI egress) and `sbx settings set platform.images.registryMirror artifactory.corp/docker-remote`. `kit.shortcuts.<agent>` maps an agent name to a kit reference. Some settings need `sbx daemon restart`; the command says so.
- `sbx daemon log-level set proxy|general|all LEVEL` raises daemon logging when debugging network issues.
- `sbx reset` returns everything to a freshly installed state: stops and deletes all sandboxes, clears images, policies and secrets, and signs out. `--preserve-secrets` keeps secrets. Suggest it only as a last resort and say what it destroys.
- `sbx logout` also stops running local sandboxes.
- `sbx completion bash|zsh|fish|powershell` prints a completion script.

## Cloud

`--cloud` targets Docker's hosted sandboxes. The same verbs behave differently, so do not carry local assumptions across:

- **No host workspace.** No PATH follows the agent; clone the project inside the sandbox. Sizing must match a billable shape: micro 1 vCPU/2 GiB, small 2/4 (the default), medium 4/8, large 8/16, xl 16/32.
- Sandboxes are addressed by ID (`sbx_*`) or name from `sbx --cloud ls`.
- `sbx --cloud run AGENT` prompts to reuse an existing sandbox; `--new` always creates, `--name NAME` reuses or creates. A non-interactive run without `--detach` is refused, so scripts use `sbx --cloud run -d claude` then `sbx --cloud exec`.
- `sbx --cloud attach SANDBOX` opens a terminal on an existing sandbox, starting it if stopped. Default detach key is Ctrl-\ (`--detach-keys` changes it).
- **Sandboxes expire.** `--ttl 2h` and `--on-timeout stop|restart|delete` at creation; `sbx --cloud ttl SANDBOX` shows the remaining time and `sbx --cloud ttl +2h SANDBOX` extends it, up to a hard 24h-from-creation ceiling.
- `sbx --cloud rm --all` is disabled on purpose; pass IDs explicitly. `prune` is local only.
- `exec` rejects `--user` and `--privileged` in cloud mode.
- Ports are the sandbox port alone (`--publish 8080`); each gets a public URL. No UDP, no host bindings.
- Policy is per account or per sandbox, has no rule IDs (remove with `--resource`), has no HTTP method/path rules, and `policy init` can be re-run.
- `sbx --cloud volume create|ls|inspect|rm NAME` manages persistent volumes, attached with `-v NAME:MOUNTPATH`. Data is snapshotted when a sandbox exits, and with concurrent mounts the last one to exit wins.
- Set cloud secrets before creating the sandbox; one added later is not picked up. With `-t/--template`, do not also pass an agent name, `--cpus` or `--memory`.
- A published cloud port is a public HTTPS URL. Put authentication in the service and unpublish when done.
- `sbx --cloud template save SANDBOX NAME [--capture-mode all]` snapshots a running cloud sandbox; `sbx --cloud run --template NAME` starts from it.
- `sbx move SANDBOX --to cloud|local [--name N]` copies a sandbox's filesystem across. Running processes, the workspace bind mount, sbx-managed secrets and locally added network rules do not travel, and the source is stopped and not deleted.

## Experimental commands

Marked experimental in the help, so check `--help` before relying on details.

**env**: declare a sandbox in `sbxenv.yaml` and manage it as a unit.

```
sbx env plan [PATH...]          # preview: host commands, secrets, MCP servers, ports. Applies nothing.
sbx env create [PATH...]        # provision and create
sbx env run [PATH...] [-- ARG...]   # create if needed, then attach (-d to skip attaching)
sbx env exec [flags] [PATH...] -- COMMAND [ARG...]
sbx env rm [PATH...] [--prune-bindings]
```

PATH is a directory containing `sbxenv.yaml` or the file itself; several are deep-merged in order, later winning. With no PATH, `~/.sbxenv.yaml` supplies defaults. The file can run lifecycle commands **on the host**, so read `sbx env plan` before approving one from a repository you do not trust; `--skip-host-commands` runs without them. `--force` approves the plan without prompting. Use the same `--name`, files and `--env-arg` values on every command addressing one environment.

**kit**: packaged agent definitions and mixins (a directory with `spec.yaml`). `sbx kit validate REF`, `inspect REF [--resolved]`, `pack DIR`, `push DIR REF [--sign]`, `pull REF`, `sign REF`, `verify REF`, `provenance REF`, and `sbx kit add SANDBOX REF` to add a mixin to an existing sandbox (its container is recreated, workspace data kept). `--offline` on `validate`/`inspect` works without the daemon or a sign-in for local directories and ZIPs. `sbx kit builder status|rm|history` manages the shared build sandbox and its cache.

**skills**: a host-side skills store linked into each sandbox's agent skills directory. `sbx skills add REPO [--skill NAME]` (Git URL or `owner/repo`), `import` (from `~/.claude/skills`, `~/.agents/skills` and similar; `--dry-run` previews), `ls`, `rm SKILL...`, `update [SKILL...]`. Edits to an existing skill are live; a newly added skill reaches a running sandbox on its next start.

**setup**: `sbx setup` detects host credentials and imports them. `sbx setup ssh` writes SSH config so `ssh <name>.sbx` connects to a sandbox with no key; `sbx setup ssh remove` undoes it.

## Recipes

**Test an installer in a clean box, from a script**

```bash
# First use on a machine: sbx policy init balanced   (one-time, otherwise a non-interactive run cannot proceed)
sbx --no-input run -d --name inst-test shell .          # workspace = current repo
sbx exec inst-test bash -lc './install.sh'; rc=$?       # runs as the sandbox user, real exit code
sbx exec -u root inst-test cat /var/log/install.log     # inspect as root if needed
sbx cp inst-test:/tmp/report.txt ./                     # pull artifacts out
sbx --no-input rm --force inst-test
```

`rc` 125 means sbx could not run the command (sandbox missing, not signed in) and 127 means command not found. Pass `-w DIR` if the script depends on its working directory. If the installer downloads things and fails oddly, run `sbx policy log inst-test` before changing the installer.

**Let an agent work without touching my checkout**

```bash
sbx run --clone --name feature-x claude .
git fetch sandbox-feature-x          # afterwards, on the host
```

**Expose a dev server**

```bash
sbx ports my-sandbox --publish 3000:3000/tcp
sbx ports my-sandbox                 # confirm the binding
```

**Clean up safely**

```bash
sbx ls
sbx prune --dry-run
sbx prune --filter until=168h        # stopped more than a week ago
```

## Scripting notes

- Use `--no-input` and `--force`. Piping `echo y` does not confirm a prompt; the command exits 1.
- Parse `--format json`, never tables. Results go to stdout; errors, warnings and progress go to stderr. `sbx ls --json` is a bare array: `jq -r '.[].name'`.
- Create workspace directories before `run` or `create`; a missing directory is an error without a terminal.
- `sbx secret rm` and `sbx mcp rm` fail when nothing matches, even with `--force`. List first.

## Version differences

**Older examples (renamed in v0.48.0).** If a tutorial uses the left side, use the right: `--detached` is `--detach`/`-d`; `sbx env --auto-approve` is `--force`; `sbx create -q` is `--no-progress`; `sbx diagnose --output` is `--format`; `sbx secret ls/rm --env` is `--env-name`; `sbx template save -d` is `--description`.

**Newer than v0.51.0 (from the release notes, not checked on a binary).** These fail on v0.51.0, and the v0.51.0 forms may fail after an upgrade:

| Version | Change |
|---|---|
| v0.53 | `sbx df` reports disk use. |
| v0.53 | `sbx logout` skips its prompt with `--yes`; v0.51.0 uses `--force`. Check `sbx logout --help`. |
| v0.53 | `sbx template ls --all --digests`. |
| v0.53 | `exec -d/--detach` and `exec --privileged` are removed. |
| v0.53 | The built-in `gemini` agent name is retired. |
| v0.53 | New settings `claude.chrome` and `egress.stalledConnectionTimeoutSeconds`. |

The docs' troubleshooting page says `sbx start NAME`. No such command exists on v0.51.0; use `sbx run --name NAME` or any `sbx exec`.

## Troubleshooting

Escalate in this order, and say what each step destroys before running it:

1. `sbx diagnose` (`sbx --cloud diagnose` for cloud). Destroys nothing.
2. `sbx daemon restart`. Keeps all sandbox data; running sessions drop.
3. `sbx reset --preserve-secrets`. Deletes every sandbox, image and policy rule, and signs you out.
4. `sbx reset`. The same, plus all stored secrets.

| Symptom | Do this |
|---|---|
| `global network policy has not been initialized` (exec exits 125) | `sbx policy init balanced` |
| Package install or API call blocked | `sbx policy log NAME`, then `sbx policy allow network ...` or answer `sbx policy approval ls` |
| Allow rule has no effect | Organization policy is enforced; local allows are inactive |
| API key errors although the secret is set | PROXY column shows `transparent`: the client bypassed the forward proxy. Do not set a real key inside the sandbox to work around it |
| `self-signed certificate in certificate chain` | Corporate TLS inspection: `sbx cp` the root CA in, then `sbx exec -u root NAME update-ca-certificates`. Do not point `SSL_CERT_FILE` at only your CA; that breaks the credential proxy |
| Certificate errors in `docker build` inside the sandbox | Build containers do not inherit the sandbox trust store. Write `$PROXY_CA_CERT_B64` (base64-decoded) to a `.crt`, `COPY` it, run `update-ca-certificates`, and pass `--build-arg HTTP_PROXY --build-arg HTTPS_PROXY --build-arg NO_PROXY` |
| Out of disk inside the sandbox | Recreate with `DOCKER_SANDBOXES_ROOT_SIZE=40g` or `DOCKER_SANDBOXES_DOCKER_SIZE=20g` set for the creating command; existing disks are not resized |
| Git index corruption or stale files on a mounted repo | Recreate with `DOCKER_SANDBOXES_ENABLE_VIRTIOFS_CACHE=0`, or use `--clone` |
| `--clone` says not a Git repository on a WSL path | Add the repo to Git `safe.directory` on the host |
| Daemon fails after a downgrade | `sbx reset --preserve-secrets` |
| Commits unsigned | Only SSH signing through the forwarded agent works: in the sandbox `git config --global gpg.format ssh` and set `user.signingkey`. GPG keys are not available |

The rows above come from the docs, except the first, which was seen on a real v0.51.0 binary.

## Reporting back

When you run sbx commands for the user, say which sandbox name you used and whether it is still running, because sandboxes hold memory and CPU until stopped. If a command failed on sign-in, the daemon or virtualization, say that plainly and point at `sbx diagnose`; do not retry the same command hoping for a different result.
