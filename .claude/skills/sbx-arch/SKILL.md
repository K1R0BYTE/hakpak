---
name: sbx-arch
description: How Docker Sandboxes (the sbx microVM agent sandbox) works inside - architecture, isolation and security model, network and credential proxy, workspace and storage model, local versus cloud sandboxes, platform requirements and exact limits. Use this whenever someone asks whether it is safe to run an agent in a sandbox, what the agent can or cannot reach, why the sandbox cannot connect to something, where secrets or API keys live, whether the agent can read .env or the host Docker daemon, what persists after stop or rm, what clone mode protects, how organization governance overrides local rules, what the disk, CPU, TTL or quota limits are, or how cloud sandboxes differ. Trigger on "is it safe to", "can the sandbox see", "why can't the sandbox", "what is the limit on", "how does sbx isolate", "threat model", "does the key enter the VM", also when only Docker Sandboxes is named. For command syntax and how-to recipes, use sbx-cli instead.
---

# Docker Sandboxes architecture, limits and security model

Use this to answer "is it safe to", "why can't the sandbox" and "what is the limit on" questions. For command syntax load `sbx-cli`.

## Scope, version and trust order

- Source: docs.docker.com/ai/sandboxes and /ai/governance, read 2026-11-13, describing up to **v0.53.0 (2026-11-11)**. A few facts were checked against `sbx --help` on v0.51.0 and are marked "(help)".
- Nothing here was observed by us on a running sandbox. Lines marked "(in-VM)" come from the guidance files sbx writes into a `shell` and a `claude` sandbox (`AGENTS.md`, `CLAUDE.md`), copied out of running sandboxes on 2026-11-14; where they disagree with the docs they win. Values tagged with a version are from that release's notes and may differ on an older binary.
- Statements describe **local** sandboxes unless a section says cloud.
- Trust order: behaviour on the machine (`sbx COMMAND --help`, `sbx policy ls`, `sbx settings ls`), then this file. Where this file says "not found in docs" or "inference", say so instead of presenting it as fact.

## One-paragraph model

Each sandbox is a lightweight **microVM with its own Linux kernel**. Inside it the agent runs as a non-root user (`agent`) with sudo, next to a **private Docker Engine**. A host-side daemon (`sandboxd`) owns the VMs, a host-side **proxy** that every outbound connection must pass, the **credential store**, and the **MCP gateway**. The only things that cross the VM boundary are the ones you share: a workspace directory, the shared skills store, policy-approved network connections, proxy-injected credentials, and MCP gateway traffic.

```
Host: sbx CLI -> sandboxd daemon -> [network proxy + policy] [credential store] [MCP gateway]
                     |
                     +-- microVM (own kernel): agent (user agent, sudo) + private Docker Engine
                           mounts: workspace (optional), shared skills store (read-only by default)
```

The docs compare the approaches like this:

| Approach | Isolation | Docker access | Use case |
| --- | --- | --- | --- |
| Sandboxes (microVMs) | Full (hypervisor) | Isolated daemon | Autonomous agents |
| Container with socket mount | Partial (namespaces) | Shared host daemon | Trusted tools |
| Docker-in-Docker | Partial (privileged) | Nested daemon | CI/CD pipelines |
| Host execution | None | Host daemon | Manual development |

The cost of full isolation is overhead: each sandbox is a VM with its own Docker daemon and its own image cache.

## Platform requirements

| Platform | Requirement |
| --- | --- |
| macOS | Sonoma 14 or later, Apple silicon only |
| Windows | Windows 11, 64-bit Intel/AMD, Windows Hypervisor Platform enabled |
| Linux | Ubuntu 24.04 or later, x86-64 or 64-bit Arm, KVM enabled, user in `kvm` group |

- The runtime requires KVM on Linux and Windows Hypervisor Platform on Windows. The macOS hypervisor is **not named in the docs**.
- Inside a VM or VDI, nested virtualization must be supported.
- Docker Desktop or Docker Engine on the host is not required. The sandbox runtime pulls images itself and does **not** share the host Docker image store.
- Ubuntu derivatives are not tested or supported.
- A Docker account sign-in is mandatory; the daemon accepts SSH connections only while a Docker login is active.
- Cloud sandboxes need none of the hypervisor setup, sbx 0.45.0 or later, and a Docker Agentic Platform subscription.

## Five isolation layers

1. **Hypervisor**: separate kernel per sandbox; no shared memory or processes with the host; processes are invisible to the host and to other sandboxes. The hypervisor boundary is the control, not in-VM privilege separation, which is why the agent may have sudo.
2. **Network**: each sandbox has its own network. No direct sandbox-to-sandbox traffic and no shared network with the host. All outbound TCP goes through the host proxy and policy.
3. **Docker Engine**: `docker build` and `docker compose up` inside the sandbox hit the sandbox's own engine. There is no path to the host Docker daemon. Containers the agent starts never appear in the host's `docker ps`.
4. **Workspace**: mountless, direct mount, or clone mode (below).
5. **Credential**: keys are injected into HTTP headers by the host proxy; values do not enter the VM.

### Blocked for every sandbox and not changeable by policy

- Host filesystem outside explicitly mounted workspaces and the shared skills store
- The host Docker daemon
- Direct network communication between sandboxes
- Direct external ICMP

## What the agent can do inside

Full control of the VM: sudo, package managers (`apt`, `pip`, `npm`), a private Docker Engine, read-write on the VM filesystem and on a directly mounted workspace. Agents are launched **without approval prompts** (for example `claude --dangerously-skip-permissions`) because the sandbox, not the prompt, is the safety boundary. New local sandboxes expose `/dev/fuse` with `SYS_ADMIN` by default (`sandbox.fuse` setting).

### Guidance sbx writes for the agent

Each sandbox carries a guidance file for the agent: `AGENTS.md` in a `shell` sandbox, `CLAUDE.md` in a `claude` sandbox (there wrapped in `sbx:guidance` comment markers, with a `sbx:kits-section` block listing installed kits). The two share the same text on environment persistence, network blocks, port publishing, host access, Git authentication and workspace mode; each then adds a part about its own kit. Copies of both were read on 2026-11-14 and are the source for every line here marked "(in-VM)". They say:

- **Base image (in-VM):** Debian trixie on Docker Hardened Images. apt sources are `deb.debian.org` and `dhi.io/deb/debian/main`. User `agent`, home `/home/agent`, passwordless `sudo`.
- **`shell` kit (in-VM):** bash, git, apt, Docker with compose and buildx, curl, gh, jq, make, Python 3 with pip and uv. It ships **no network policy of its own**: even its apt sources are reachable only if the sandbox policy or another kit allows them.
- **`claude` kit (in-VM):** Claude Code at `~/.local/bin/claude`, started by the image entrypoint as `claude --dangerously-skip-permissions`, with `permissions.defaultMode = "bypassPermissions"` in `~/.claude/settings.json`. Skills are read from `~/.claude/skills`, where the host's shared skills store mounts. Kit context files sit under `/home/agent/.claude/kits-agent-context/` and `/usr/share/sandbox/kit/KIT/context.md`.
- **Persistent environment (in-VM):** `/etc/sandbox-persistent.sh` is sourced by every shell (`BASH_ENV`, `/etc/profile.d/`, `/etc/bash.bashrc`) and by Claude Code before each Bash call (`CLAUDE_ENV_FILE`). It lives on the VM disk, so it lasts as long as the sandbox does.
- **Identity (in-VM):** the sandbox name is in `$SANDBOX_NAME` and is the hostname.

## Workspace and filesystem model

| Mode | How | Host exposure | Agent's changes reach host |
| --- | --- | --- | --- |
| Direct mount | `sbx run AGENT [PATH]`, or `sbx create AGENT PATH` | Directory shared read-write | Immediately, no sync step |
| Clone mode | `--clone` on a Git repo | Repo Git root mounted **read-only** at `/run/sandbox/source`; agent edits a private clone in the VM | Only when you `git fetch sandbox-<name>` or the agent pushes |
| Mountless | `sbx create AGENT` with no path | No host workspace | Only via `sbx cp` or a Git remote |
| Host worktree as workspace | pass the worktree dir | Worktree dir read-write | Immediately; agent has **no Git** (the `.git` pointer cannot resolve) |

Facts that answer most questions:

- A directly mounted workspace appears at the **same absolute path** as on the host. Extra workspaces may take a custom target and may be read-only (`:ro`).
- Mounts use a filesystem passthrough (virtiofs). Virtiofs read caching is on by default on all OSes; disable with `DOCKER_SANDBOXES_ENABLE_VIRTIOFS_CACHE=0` at creation if you see Git index corruption. Clone mode always enables it.
- Do not use network drives, SMB/NFS shares or cloud-synced folders as a workspace: every read and write then crosses the network.
- Mountless and Docker-provided templates use `/home/agent/workspace` as the working directory (image `WORKDIR`, with that path as fallback).
- Symlinks pointing outside the workspace are not followed. **Hard links are different**: if a workspace file is a hard link to a file outside it, the agent can read and modify the underlying file, and filesystem policies do not catch this because they evaluate the workspace path.
- Workspace configuration is fixed at creation.
- Git ignore rules do not restrict what the agent can read.

### Clone mode guarantees and non-guarantees

Guaranteed: the agent cannot modify any tracked file, the working tree, or any byte under `.git/` on the host, even as root in the VM. It cannot plant a `.git/hooks/pre-commit` or alter CI files. There is no shared writable Git state, so host and sandbox Git commands cannot race. Host `.git/config` credentials and signing settings stay on the host.

**Not** guaranteed: confidentiality. The whole Git root is readable inside the sandbox, including untracked and `.gitignore`d files such as `.env`. Keep secrets outside the working directory.

Mechanism: the sandbox publishes the clone through a Git daemon bound to host localhost on an ephemeral port; the CLI adds a `sandbox-<name>` remote to the host repo and rewrites its URL after restarts. Fetching has the same trust model as any third-party remote. Fetch remotes such as `origin` are copied into the sandbox under the same names with embedded credentials removed; local-path, push-only, helper-backed, custom-transport and ambiguous remotes are not (in-VM). The clone's `HEAD` is the host checkout at creation and no branch is created. The Git daemon runs only while the sandbox is up. The read-only host repo at `/run/sandbox/source` is how the agent sees commits the host makes later (in-VM). `sbx rm` deletes clone, daemon, port and remote.

### What persists

| Event | Kept | Lost |
| --- | --- | --- |
| Agent exits or `sbx stop` | Installed packages, Docker images and containers, config changes, command history, agent state, mountless and cloned workspace files | Nothing listed in the docs; temporary kit storage is discarded on stop |
| `sbx rm` | Host workspace files, clone-source repos, shared skills store, persistent kit volumes, cached template images | The VM, its filesystem, Docker images, the in-sandbox clone (with any commits not yet fetched), sandbox-scoped policy rules, and secrets scoped to that sandbox (help) |
| `sbx reset` | Nothing unless `--preserve-secrets` | All sandbox data, cached images, the skills store, local policy rules and stored secrets; it also signs you out (help) |

Where things live on the host:

| Data | Location |
| --- | --- |
| Sandbox state | macOS `~/Library/Application Support/com.docker.sandboxes/`; Windows `%LOCALAPPDATA%\DockerSandboxes`; Linux `~/.local/state/sandboxes/`, `~/.cache/sandboxes/`, `~/.config/sandboxes/` |
| Secrets | OS keychain; file fallback described under "Credential model" |
| Credential binding approvals (no values) | `~/.config/sbx/credentials.yaml`; Windows `%APPDATA%\sbx\credentials.yaml` |

Sandboxes do **not** share images or layers with each other. Updating the CLI or a template does not update the agent inside existing sandboxes.

## Resource limits and defaults

| Item | Value |
| --- | --- |
| Root filesystem `/` | 20 GB default per the docs (not confirmed on a binary); `DOCKER_SANDBOXES_ROOT_SIZE` at creation |
| Docker data disk `/var/lib/docker` | 10 GB default (`sandbox.disk.dockerVolume` = `10g`); minimum 512 MiB; `DOCKER_SANDBOXES_DOCKER_SIZE`; existing volumes are not resized |
| Cloned workspace volume | set with `DOCKER_SANDBOXES_CLONED_WORKSPACE_SIZE`, for example `100g`; default not found in docs |
| CPUs | default 0 = all host CPUs, capped at 16 on Linux arm64; explicit count up to available host CPUs |
| Memory | minimum 512 MiB; default 50% of host memory, clamped to 512 MiB to 32 GiB; maximum is total host memory, with a warning above 75% (help) |
| Clipboard image paste | off by default; images over 64 MiB are ignored |
| Stalled outbound connection timeout | 30 seconds default, range 0 to 3600, 0 disables (v0.53 setting `egress.stalledConnectionTimeoutSeconds`) |
| Dynamic secret cache | 55 minutes default for service secrets |
| Daemon log rotation | 50 MB, 3 backups |
| Unused source-kit build images | eligible for cleanup after 7 days (v0.53) |
| Kit port-publish approval request | expires after 45 seconds (v0.51) |
| OAuth callback | times out after 60 seconds (v0.53) |
| Organization policy propagation | up to 5 minutes |
| Cloud-to-local move | may need up to 32 GiB temporary host disk |
| Published ports (local) | protocols `tcp`, `tcp4`, `tcp6`, `udp`, `udp4`, `udp6`; no protocol means `tcp4` on 127.0.0.1 (help) |
| Refused-UDP logging | first 20 distinct destinations per sandbox network logged individually, the rest grouped |
| Audit log API | 30-day window per request |

GPU passthrough (experimental): x86-64 Linux hosts only, NVIDIA only, via VFIO, needs a GPU nothing else is using, IOMMU on, `iommufd` and `vfio_pci` modules, and a driver bundle at `/usr/libexec/nerdbox-nvidia-bundle.erofs` that must be rebuilt after each sbx upgrade because it must match the guest kernel.

Maximum number of local sandboxes: not found in docs. Each sandbox costs disk for its VM image, Docker images, layers and volumes.

## Network model

### Path of a request

All outbound TCP leaves through a proxy on the host. Clients that honor the proxy settings use the **forward proxy** (HTTP and HTTPS); everything else is caught by a **transparent proxy**. Both enforce policy; **only the forward proxy injects credentials**, and on that path the proxy terminates TLS and presents its own certificate, which the sandbox trusts (the CA is available inside as `PROXY_CA_CERT_B64`).

1. The agent builds a request holding a sentinel instead of the real credential.
2. The request leaves the microVM.
3. Policy checks the destination; it continues only if a rule permits it.
4. The host proxy looks up the matching credential on the host.
5. The proxy rewrites the header after the request has left the VM.
6. The response returns through the proxy.

| `sbx policy log` PROXY value | Meaning |
| --- | --- |
| `forward` | Forward proxy, credential injection available |
| `forward-bypass` | Forward proxy, no TLS termination, no injection |
| `transparent` | Transparent proxy, policy enforced, no injection |
| `network` | Non-HTTP traffic |
| `browser-open` | Sandbox asked to open a URL in the host browser; policy checked first |

Consequence: a process that ignores the proxy settings (often a process inside a nested container) reaches allowed hosts but gets no credentials. Containers started by the sandbox's Docker Engine have their own trust stores and do not inherit the sandbox's CA.

### Protocols

| Traffic | Behaviour |
| --- | --- |
| Outbound TCP (HTTP, HTTPS, SSH, anything) | Blocked unless a rule matches the destination |
| Outbound UDP | Disabled by default. Experimental opt-in (`feature.udp-egress`) plus UDP allow rules. Never to multicast, link-local, unspecified or broadcast addresses, and never where an upstream HTTP, SOCKS5, system or PAC proxy is needed. mDNS and SSDP cannot work |
| ICMP | Always blocked; cannot be unblocked |
| DNS | Answered by the sandbox's internal resolver, which enforces policy. For non-HTTP TCP the hostname is recovered from the resolver, so hostname rules work unless the client connects by raw IP |
| Sandbox to sandbox | Not possible directly |
| Sandbox to host loopback services | `localhost` and `127.0.0.1` are the sandbox itself. Use `host.docker.internal`; the proxy maps it to the host's `localhost`, and policy must allow `localhost:PORT` |
| Sandbox to host services on other addresses | Reachable directly at that address, such as the LAN IP, when policy allows it (in-VM; the docs used to say the LAN IP does not work) |
| Host to sandbox | Only through published ports, bound to `127.0.0.1` by default, or SSH port forwarding to sandbox loopback. A published port reaches the sandbox's `eth0`, so the service must listen on `0.0.0.0` or `::` (in-VM) |
| Sandbox to its own Docker containers | Published container ports work on `localhost`, which is in `NO_PROXY`. A container network must be added to `NO_PROXY` to reach container IPs directly (in-VM) |
| Inbound from the network | None unless you bind a published port or SSH forward to a non-loopback address |

### Default allow and deny behaviour

The fallback is deny (`default-deny-all`). What is open depends on the preset chosen at first run:

- **Open** (`allow-all`): all outbound TCP allowed.
- **Balanced** (`balanced`): default deny plus a baseline allowlist: AI provider APIs, package managers, OS package repositories, code hosts, container registries, cloud services, certificate validation. The exact list is not printed in the docs; `sbx policy ls` shows it. It includes broad wildcards such as `*.googleapis.com`.
- **Locked Down** (`deny-all`): no baseline; only your rules and kit rules.

Rule combination without organization governance: allowed if any rule (local or kit) allows, and **any deny wins**. Kit rules apply under every preset. Under Balanced and Locked Down an unmatched request is blocked and recorded as an approval request; approving creates a rule for that exact destination and port, scoped to that sandbox, and only helps later requests.

HTTP (L7) rules can match method, path and query on a hostname; path and query matching ignores ASCII case. A host deny is a floor HTTP allows cannot raise; a host allow is a ceiling HTTP denies can carve into. A connection the proxy cannot inspect (transparent path) is **blocked** when an HTTP decision is required. The policy log records hosts only, not methods or paths.

Policy is enforced outside the sandbox, so the agent cannot change or bypass it.

What the agent sees when blocked (in-VM): an **HTTP 403** whose body names the cause. `Approval required for HOST` means a pending approval; `Blocked by local rule for HOST` means a local deny, which no allow overrides; `Blocked by org policy` deliberately omits the rule; `Blocked by network policy: domain HOST` with `rule`, `origin` and `detail` lines is the default deny or an explicit deny. `sbx-cli` has the response to each.

The proxy detects whether the host is IPv4-only, IPv6-only or dual-stack and can get it wrong, which shows as connection errors or very slow requests rather than 403s. `DOCKER_SANDBOXES_IP_STACK` (`ipv4only`, `ipv6only`, `dual-stack`) set for the daemon overrides the detection (in-VM).

### Upstream and corporate proxies (experimental)

The host proxy makes outbound connections with the host's routing and, by default, the OS system proxy (including PAC). Only HTTP and HTTPS can be chained to an upstream proxy. Sandbox traffic and daemon traffic can be routed separately (`proxy.sandbox`, `proxy.daemon`). `no_proxy` exclusions do not grant access; policy still applies. Windows integrated auth (NTLM/Kerberos) happens on the host. Existing sandboxes pick up proxy changes only after `sbx daemon restart`.

## Credential model

- Stored secrets live on the **host**: macOS Keychain, Windows Credential Manager, Linux Secret Service (GNOME Keyring, KDE Wallet). Without a Secret Service (headless, some WSL) sbx falls back to a file under `$XDG_CONFIG_HOME/com.docker.sandboxes` (default `~/.config/com.docker.sandboxes`) in a `0700` directory; anyone who can read that file can read the secrets.
- The sandbox sees a sentinel such as `proxy-managed`, never the value. Injection is limited to the domains the service or kit declares. For the built-in services those include:
  - `anthropic`: `api.anthropic.com`, `console.anthropic.com`, `claude.ai`, `mcp-proxy.anthropic.com`
  - `openai`: `api.openai.com`, `openai.com`, `chatgpt.com`, `www.chatgpt.com`
  - `github`: `api.github.com`, `github.com`, `raw.githubusercontent.com`, `gist.github.com`, `copilot.github.com`, `api.githubcopilot.com`
  - `google`: `generativelanguage.googleapis.com`, `oauth2.googleapis.com`, `aiplatform.googleapis.com`, `vertexai.googleapis.com`
- A secret can be a reference (`op://`, AWS ARN) or host command; resolution and caching happen on the host. The helper runs with your privileges, so keep it outside any directory a sandbox can write, or the agent could change what runs on the host.
- Custom secrets put a generated placeholder (`sbx-cs-...`) in an env var; the proxy replaces it only in HTTP request **headers** to the configured hosts, never in bodies.
- OAuth flows (Claude Code, Codex, Cursor, Droid) run host-side; tokens stay on the host.
- In a `claude` sandbox (in-VM) either the `apiKeyHelper` in `~/.claude/settings.json` returns the literal `proxy-managed` and the proxy substitutes the real key on requests to `api.anthropic.com`, or `~/.claude/.credentials.json` holds claude.ai OAuth tokens that are sentinels swapped at request time. With nothing bound, `claude` asks for `/login`.
- GitHub (in-VM): the proxy injects the token into HTTPS Git operations, so `gh auth status` reports "not logged in" and pushes still work. A secret scoped to one sandbox applies to it immediately; a global secret applies to sandboxes created afterwards.
- Registry credentials stay on the host; host-only scope is never visible to sandboxes, the other scopes let the proxy answer registry logins.
- Third-party kits need an explicit **credential binding** approval per service and domain; built-in kits do not. In a non-interactive run a missing binding means the credential is withheld with a warning, and the sandbox still starts.
- No credentials are available by default.
- SSH agent forwarding is **on by default**: private keys stay on the host, but any process in the sandbox can ask the agent to authenticate or sign. Turn off with `ssh.agentForwardingEnabled false`. GPG and S/MIME keys are not available.
- SSH access to a sandbox (`NAME.sbx`) terminates at the daemon over its local socket; no SSH server runs in the sandbox, no network port or SSH key is used, and client environment variables are not forwarded.

### Ways credential isolation is weakened

The first two are stated plainly in the docs. The last three each rest on a single docs page and were not verified.

- You set a key as an environment variable or write it to a file: it is readable by every process, and is captured by `sbx template save` and `sbx move`.
- A kit sets OAuth `passthrough: true`: the real token enters the sandbox.
- Claude Desktop over SSH can write Anthropic credentials into the sandbox during OAuth refresh.
- Kiro stores its auth in `~/.local/share/kiro-cli/data.sqlite3` inside the sandbox; Gemini interactive sign-in is sandbox-scoped.
- Model-provider keys used with `--provider` go to the host `llmman` service, which can forward the key to other endpoints it supports; the usual per-domain restriction does not apply.

## Is it safe to ... (answer key)

| Question | Answer |
| --- | --- |
| Let an agent run with permission prompts off? | That is the designed mode; the VM, network policy and credential proxy are the boundary. Prompts can be re-enabled in the agent if wanted. |
| Trust files after a direct-mount session? | No. Treat them like a pull request from an untrusted contributor. Check files that execute implicitly: `.git/hooks/` (not shown by `git diff`; run `ls -la .git/hooks/`), CI configs, `Makefile`, `package.json` scripts, `.vscode/tasks.json`, `.idea/`, `.claude/`, `.codex/`. |
| Keep `.env` in the repo with clone mode? | Not for secrecy. Clone mode prevents modification, not reading. |
| Can the agent reach my host Docker, other containers, home directory, `~/.ssh`? | Host Docker: never. Host files: only paths you mount. It can ask the forwarded SSH agent to sign, without reading the key. |
| Can it read my API keys? | Not proxy-managed ones. Yes for anything you placed in env vars or files. |
| Can it exfiltrate workspace data? | Inference, not a docs statement: anything the agent can read, including `.env` in clone mode, can be sent to any destination policy allows. The Balanced defaults include broad wildcards, so prune them or use Locked Down with specific rules for sensitive work. |
| Can two sandboxes attack each other? | No network path. They do share host-side state you configure once: global policy rules, global secrets, MCP registrations and any directory mounted into both. The shared skills store is the exception: a `readwrite` sandbox can alter skills that `readonly` sandboxes later load. Use `--skills=off` to stay out. |
| Are local MCP servers sandboxed? | No. Local stdio MCP servers, and Docker containers they start, run on the **host** with host permissions. Treat them as trusted host integrations. Remote MCP servers run elsewhere. |
| Is an `sbxenv.yaml` safe to keep in the workspace? | Risky: it can declare lifecycle, secret and MCP commands that run on the host with your privileges. Keep it outside writable mounts. In a workspace root it is mounted read-only by default; in a subdirectory it can be replaced by renaming the parent. Host commands need plan approval on every invocation by default. |
| Is a kit safe? | Kits run install commands as root inside the sandbox and can add network allow rules. Sources default to `docker.io/` and `dhi.io/` (`kit.allowedSources`); signatures can be required. A signature covers `spec.yaml` and `files/`, not image tags or downloads the kit performs. |
| Is the clipboard exposed? | Host clipboard image reads are opt-in. For text: the isolation page says sandboxes can write text to the host clipboard but not read it; the v0.51.0 notes say text copy now needs the `clipboard.textCopy` setting. Check clipboard contents before pasting after untrusted code. |
| Can the sandbox open my browser? | Yes by default (`browser.enabled` true), subject to policy; disabling also blocks in-sandbox OAuth logins that redirect to localhost. |
| Is a cloud published port private? | No. It is a public HTTPS URL; add authentication in the service. |
| Does a template or `sbx move` carry secrets? | Managed secrets no; credentials written to the filesystem yes. |
| Why does `ping` fail, or HTTP/3? | ICMP is always blocked. UDP is off unless the experimental feature is enabled. |
| Why is `curl` fine but `docker build` fails on certificates? | Build containers do not inherit the sandbox's proxy CA. |
| Why is my allow rule ignored? | An organization policy is enforced, so local allow rules are inactive. |

## Organization governance

Available on a separate paid plan (AI Governance). Admins define policies in Docker Home; they apply to licensed members, org-wide or per team.

- Three policy types: **network**, **filesystem** (which host paths may be mounted; actions `read` and `write`; a writable mount needs both; rules control mounts, not individual files), **MCP** (Cedar; registration, tool calls, gateway built-in tools, resources, prompts).
- Evaluation: **default deny** and **deny wins**. Allows are additive across effective policies; an org-wide deny cannot be overridden by a team policy.
- When an organization policy is enforced: organization allow and deny are evaluated; local and kit **allow rules are inactive**; local and kit **deny rules still apply** and beat an approval requirement. Rules created by approving an org-required approval stay active.
  | Rule | Evaluated under organization policy |
  | --- | --- |
  | Organization allow, organization deny | Yes |
  | Local deny, kit deny | Yes |
  | Local allow, kit allow | No |
- Organization policies apply only when the developer is signed in as a licensed member of the organization.
- **Fail closed**: if no valid organization policy can be obtained (unresolved governance, stale snapshot, expired session), every network request and workspace mount is blocked.
- Changes reach machines within 5 minutes or on `sbx policy refresh`; already open connections stay open until the sandbox restarts.
- Sign-in enforcement (managed config listing `allowedOrgs`; macOS preferences domain `com.docker.sbx`, Windows registry, Linux `/etc/docker-sbx/config.json`) stops users bypassing policy with a personal account.
- Audit logs record policy decisions and session lifecycle as metadata only, never prompts, agent output or parameter values; cloud retention 90 days; cover local sandboxes only.
- Local policy alone covers only the network; without organization policy nothing restricts which paths you mount or which MCP servers you register.

## Local versus cloud sandboxes

| Aspect | Local | Cloud (`sbx --cloud`) |
| --- | --- | --- |
| Compute | Host resources, free | Docker-managed, pay-as-you-go |
| Workspace | Host mounts or clone mode | No host paths; `cp` files in or clone inside |
| Hardware | GPU, USB, display, nested virtualization possible | None |
| Ports | Bound to host addresses | Public HTTPS URL per sandbox port, TCP only |
| Secrets | Local store | Separate cloud store; no `--ref`/`--command`, no registry credentials |
| Network policy | Local, kit and organization policy, with HTTP method/path rules | Separate account and sandbox policy; network only; no L7 rules, no `--protocol` |
| MCP | Local gateway and registrations | Servers connected in Docker Agentic Platform |
| Lifetime | Until removed | TTL plus timeout action |
| Audit logs | Covered by organization audit logs | Not covered |

Cloud limits:

| Item | Value |
| --- | --- |
| Sizes (CPUs / memory) | micro 1 / 2 GiB, small 2 / 4 GiB (default), medium 4 / 8 GiB, large 8 / 16 GiB, xl 16 / 32 GiB; other pairs rejected |
| TTL | default 1 hour; extensions cannot pass 24 hours from creation; `--ttl 0` is an error; `restart` action needs TTL of at least 1 hour |
| On timeout | `stop`, `restart` or `delete`; default stops what can be resumed and deletes the rest; volume-backed sandboxes must use `delete` and cannot be stopped |
| Platforms | `linux/amd64`, `linux/arm64`, subject to account |
| Names | 2 to 63 characters, ASCII letters, digits, hyphens; `default` reserved |
| Default account quotas | 10 concurrent sandboxes, 50 stored sandboxes, 100 volumes, 100 secrets, 3 images preparing at once |
| Interrupted env creation | retry within 23 hours |

Cloud caveats: a stopped sandbox keeps memory and filesystem and is not billed for compute; `docker exec`, `docker compose exec` and healthchecks inside a cloud sandbox can hit the VM filesystem instead of the container's (known limitation); volumes snapshot on sandbox exit and the last writer wins; cloud custom secrets inject by destination host without needing the placeholder; FUSE, `--model`, host-backed skills and `long-running` kits are not available; `cp` drops permissions, timestamps, empty directories and symlinks. `sbx move` copies a filesystem snapshot only (no processes, memory, mounts, managed secrets or policy), requires the same CPU architecture, and never deletes the source: moving to cloud stops the local sandbox, and moving to local asks the cloud one to stop (help).

## Known limitations and non-goals stated in the docs

- Direct mount gives no boundary between agent edits and the host working tree.
- Hard links in a workspace bypass path-based checks.
- Clone mode does not hide repository contents.
- Shared skills put participating sandboxes in one trust boundary.
- Local MCP servers run outside the isolation.
- SSH agent forwarding lets sandbox processes use host keys for signing.
- In-VM privilege separation is not a control.
- Balanced defaults include broad wildcards.
- A sandbox is not updated in place: agent versions, kit sets and most options are frozen at creation.
- Downgrading sbx can leave a state database the older binary cannot read.
- Telemetry: the CLI records command, success, duration and Docker username, not prompts or code.
- Kit capability gaps the docs note: cloud sandboxes keep installation-phase network access and credentials after setup.
- The docs' own framing: "The sandbox isolates the agent from your host system, but the agent's actions can still affect you through explicitly shared resources and allowed network channels."

## Treat as unverified

These appear in the docs or were inferred from them, and nobody confirmed them on a running sandbox: the 20 GB root disk default; "retry within 23 hours" for interrupted cloud env creation; that `sandboxd` is the single owner of all four host components; the `llmman`, Claude Desktop and Kiro credential cases; the sign-in enforcement paths, the secret fallback file path and the GPU bundle path. Give them with that caveat.

## Not found in docs

The macOS hypervisor and the VMM implementation, the default clone-workspace volume size, any cap on the number of local sandboxes, the full Balanced allowlist, the DNS resolver implementation, guest kernel version, and cloud pricing figures.
