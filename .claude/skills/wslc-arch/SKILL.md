---
name: wslc-arch
description: How WSL containers (wslc.exe, the container runtime built into Windows Subsystem for Linux) work inside - architecture, session VM model, storage, networking, isolation and security model, enterprise policy, and exact limits and defaults. Use this whenever someone asks whether it is safe to run something in a WSL container, what a container can or cannot reach on Windows, where images, volumes and registry credentials live, what survives a session shutdown, why elevated and normal terminals see different images, how ports and host access work, what the CPU, memory, disk or idle limits are, how .wslconfig relates to settings.yaml, or what Intune and Defender can control. Trigger on "is wslc a sandbox", "can the container see", "where does wslc store", "what is the limit on", "how does wslc isolate", "threat model", "wslc vs Docker Desktop architecture", also when only WSL containers is named. For command syntax and recipes, use wslc-cli instead.
---

# WSL containers: architecture, limits and security model

Use this to answer "is it safe to", "what can the container reach" and "what is the limit on" questions. For command syntax load `wslc-cli`.

Nothing here was observed on a live `wslc.exe`.

Sources, read 2026-11-13. Each statement below is tagged so you know how far to trust it:

- **[docs]** Microsoft Learn: `wsl-container.md`, `wsl-container-settings.md`, `tutorials/wsl-containers.md` (MicrosoftDocs/WSL). Authoritative but thin: they cover setup, settings and the API, and say almost nothing about internals or security.
- **[blog]** Microsoft's public preview (2026-06-29) and general availability (2026-09-29) announcements.
- **[src]** The open-source implementation, microsoft/WSL at release 3.0.5, including its `security.md`. This is what the product does, but implementation details are not a documented contract and can change between releases.

Answer from this file. Where it says "not documented", say so instead of guessing. If observed behaviour disagrees with this file, trust the tool (`wslc system info`, `wslc version`).

## One-paragraph model

`wslc.exe` is a thin Windows client. It talks over COM to the WSL service, which creates a **session**: a lightweight Hyper-V utility VM running Microsoft's Linux kernel, with **containerd and dockerd** inside it. Containers are ordinary Linux containers on that shared kernel. Images, containers and volumes live on a virtual disk (`storage.vhdx`) attached to the VM. The VM starts on demand and shuts down when idle. [src] [blog]

```
Windows user process: wslc.exe / container.exe / app using Microsoft.WSL.Containers
        | COM
        v
wslservice.exe (SYSTEM): session manager, creates VMs (HCS), enforces who may open which session
        | launches, inside a per-session job object
        v
wslcsession.exe (runs as the user): owns one session, relays I/O and ports, holds the policy checks
        |
        v
Utility VM (WSL 2 kernel): init -> containerd -> dockerd -> your containers
   disks: storage.vhdx at /var/lib/docker, swap.vhdx (ephemeral)
   shares: Windows folders via VirtioFS (only the ones you mount)
   network: consomme (default) relays traffic through Windows
```

Two front ends use the same service: the CLI, and the **WSL container API** (NuGet `Microsoft.WSL.Containers`, with C, C# and C++/WinRT projections; the C++/WinRT one is in preview). API objects mirror the lifecycle: `WslcService` (prerequisite checks), `Session`, `Container`, `Process`. An application creates its **own** session with its own name, storage path, CPU and memory, separate from the CLI's. [docs]

## Requirements

| Item | Value | Source |
|---|---|---|
| WSL version | 2.9.3 or later; update with `wsl --update` | docs |
| Separate engine | None. `wslc.exe` ships inside WSL | docs |
| Docker Desktop | Not required and not used. The two coexist with separate image stores | src |
| Windows edition, CPU architecture, nested virtualization | Not documented for containers specifically. It runs on the WSL 2 virtual machine platform, so WSL 2's own requirements apply | - |
| Container OS | Linux images only, host architecture only (no `--platform`) | src |

## Sessions

A session is the unit of isolation and of state: one VM, one engine, one disk. [src]

- **Default sessions are per user and per elevation level.** The CLI's default session is named `wslc-cli-<username>` for a normal terminal and `wslc-cli-admin-<username>` for an elevated one. They are different VMs with different disks, so an image pulled in one is not visible in the other. Names starting with `wslc-cli` are reserved and cannot be created by callers. [src]
- **Start on demand, stop when idle.** The VM boots on the first command (30 s boot timeout) and is torn down after `session.idleTimeout` seconds with no activity, default 30. [docs] [src]
- **What counts as activity:** in-flight operations, any container that exists in a created or running state, and attached client processes. So a session with a running container stays up; a session with only stopped containers and images shuts down and frees its memory. [src]
- **What survives shutdown:** everything on `storage.vhdx`, meaning images, stopped containers, named volumes and build cache. Running processes do not survive. Containers created with `--restart always` are restarted by the engine the next time the session starts. Swap is recreated each boot. [src]
- `wslc system session terminate` stops the VM immediately; the next command starts a fresh one with current settings. [docs]
- `wslc system session enter <empty dir>` creates a temporary, non-persistent session that is deleted when its shell exits. A session created without a storage path keeps its engine data on tmpfs, so nothing persists. [src]

## Storage

| What | Where | Source |
|---|---|---|
| Session disk | `<storagePath>\wslc\sessions\<session>\storage.vhdx`, with `storagePath` defaulting to `%LOCALAPPDATA%` | docs |
| Inside the VM | The disk is mounted at `/var/lib/docker` (ext4) | src |
| Swap | `swap.vhdx` next to it, deleted and recreated on every VM start | src |
| Settings | `%LOCALAPPDATA%\wslc\settings.yaml` | docs |
| Registry credentials | Windows Credential Manager (default), or a DPAPI-encrypted file `%LOCALAPPDATA%\wslc\registry-credentials.json` when `credentialStore: file` | docs |

- The disk grows as needed up to `session.maxStorageSize`, default **1 TB**. That is a ceiling, not a reservation. [docs]
- **Changing `storagePath` does not move data.** The old disk stays where it was and a new empty session is created at the new path. [docs]
- Named volumes use the `guest` driver (a directory on the session disk) or the `vhd` driver (a separate virtual disk). [src]
- **Bind mounts** share a Windows folder into the VM over **VirtioFS** by default (`plan9` is the alternative). Microsoft quotes up to 2x faster Windows file access than before. Only folders you mount are shared; there is no automatic `/mnt/c` inside containers. [blog] [src]
- Files written by containers into a bind mount land on the Windows file system with the invoking user's access. A container can read and write everything in a folder you mount read-write.

## Networking

- **Default mode is `consomme`**, new with WSL containers: Linux traffic is relayed through Windows, so containers inherit the host's VPN, proxy, firewall and enterprise network policy. Microsoft called it experimental at preview. Alternatives are `nat` and `none` (`session.networkingMode`, present in the source but not in the documented settings table). [blog] [src]
- **DNS tunneling** is on by default: container DNS queries are answered through Windows. [src]
- **Published ports bind to `127.0.0.1`** unless you give a host IP or set `session.defaultBindingAddress` (for example `0.0.0.0` for all interfaces). Containers are not reachable from the LAN by default. [docs]
- **Reaching Windows from a container:** the name `host.wslc.internal` resolves to the host (`session.hostLoopback`; `none` disables it). [docs]
- `--network host` is rejected. Per-container modes are `bridge`, `none`, `container:<name>` and user-defined bridge networks with name-based DNS. [src]
- UDP ports exposed by an image are not published by `-P` in the current mode. [src]
- **TLS:** the host's trusted root certificates (machine and user stores) are copied into the VM before the engine starts, so pulls through a TLS-inspecting corporate proxy work without extra setup. This applies to the engine, not automatically to the trust store inside each container image. [src]

## Security model

The short version: **a WSL container is a convenience and compatibility boundary, not a sandbox for hostile code.** Microsoft's own security document for WSL says so directly. [src: `doc/docs/technical-documentation/security.md`]

What Microsoft states:

- Code running in WSL has the same trust level as the Windows account that launched it. WSL "is not a security sandbox for running untrusted code".
- "Containers running inside WSL inherit the security properties of their container runtime configuration and WSL. Running a workload in a container does not make WSL a security boundary from the Windows host."
- To isolate untrusted code, use a boundary built for it, such as a separately managed virtual machine outside WSL.
- Configuration settings are product behaviour, not containment, unless explicitly documented as a security control.

What the implementation does give you [src]:

| Layer | Property |
|---|---|
| Container vs container | Standard Linux namespaces and cgroups from dockerd. All containers in a session share one kernel and one engine. |
| Container vs Windows | A VM boundary sits in between, but it is deliberately porous: mounted folders, published ports, the host network path and `host.wslc.internal`. |
| User vs user | A non-elevated caller can open only sessions owned by the same Windows account (same SID). Each user has their own default session and disk. |
| Elevated vs non-elevated | A non-elevated process cannot open an elevated session. **An elevated process can open any session on the machine**, including other users'. The source marks proper ACL checks as future work. |
| Session process | `wslcsession.exe` runs as the user inside a per-session job object, so it is cleaned up if it crashes. VM creation is done by the SYSTEM service on its behalf. |
| Privilege flags | No `--privileged`, `--device`, `--security-opt`, `--pid` or `--ipc` on `wslc run`. `--cap-add` and `--cap-drop` exist. No USB or serial passthrough. |
| GPU | GPU support is enabled for every session and exposed to a container with `--gpus all`. There is no setting to turn it off yet. |
| Docker socket | There is no Docker API endpoint on Windows. dockerd listens only inside the VM, so tools that expect `/var/run/docker.sock` or a named pipe do not attach. |

Practical consequences when advising someone:

- Anything in a bind-mounted folder is fully exposed to the container, and through it to whatever the container downloads. Mount the narrowest folder, and read-only where possible.
- A container has the same outbound network reach as the user's Windows session, including VPN-only and intranet hosts, and can reach services listening on the host through `host.wslc.internal`. There is no per-container egress allowlist.
- Root inside a container is not Windows administrator, but it is root on a kernel shared with every other container in that session.
- For running untrusted or agent-generated code, prefer a purpose-built sandbox or a separate VM. If wslc is used anyway, use a throwaway session (`session enter`), no bind mounts, `--network none` where possible, and `--cap-drop ALL`.
- Build secrets passed with `--secret type=file` are mounted read-only from their original location for the build only; the file's sibling files in that directory are visible to the build VM for that time. Secrets from environment variables are delivered at `/run/secrets/<id>`.

## Enterprise controls

| Control | What it does | Source |
|---|---|---|
| Allow WSL containers access (Intune / Group Policy) | Turns the whole feature on or off | blog |
| WSL containers registry allow list (policy `WSLContainerRegistryAllowlist`) | Restricts which registries images may be pulled from or pushed to. Enforced in the service, so it covers the CLI, the API and any other client, and it is also applied to base images during `wslc build` through a BuildKit source policy snapshotted at VM boot | blog, src |
| Microsoft Defender for Endpoint plugin | Surfaces process, file and network activity from containers and ties it to the Windows host | blog |
| WSL plugins | The service notifies registered WSL plugins when a session is created and can abort creation if a plugin rejects it | src |

A blocked pull fails with a "registry blocked by policy" error. That is an administrator decision, not something to work around.

## Limits and defaults

| Item | Default | Bounds and notes | Source |
|---|---|---|---|
| Session vCPUs (`session.cpuCount`) | All logical processors | Must be above 0 | docs |
| Session memory (`session.memorySize`) | 50% of host RAM | Minimum 1 MB; a ceiling for the whole VM, shared by all containers | docs |
| Session disk (`session.maxStorageSize`) | 1 TB | Grows on demand | docs |
| Idle shutdown (`session.idleTimeout`) | 30 s | Must be above 0 | docs |
| VM boot timeout | 30 s | Not configurable | src |
| Port bind address | 127.0.0.1 | `session.defaultBindingAddress` | docs |
| Host name for Windows | `host.wslc.internal` | `none` disables | docs |
| Stop grace period | 5 s reported for `wslc stop`, versus Docker's 10 s | Community testing on 2.9.4, not in Microsoft's docs | - |
| Per-container limits | None unless set | `--memory`, `--cpus`, `--shm-size`, `--ulimit`, bounded by the session | src |
| Restart policies | `no`, `always` | `on-failure` and `unless-stopped` rejected | src |
| Compose, Swarm, Kubernetes, multi-platform builds | Not available | `wslc compose` is announced as the next focus | blog |
| Windows containers | Not supported | Linux only | - |

Size values take `B`, `K`/`KB`, `M`/`MB`, `G`/`GB`, `T`/`TB`, `P`/`PB`, case-insensitive and binary (1 GB = 1024 MB); a bare number is bytes. [docs]

Settings timing: `session.*` values are read when the session VM starts, so terminate the session to apply them. `defaultBindingAddress` and `credentialStore` are read on every command. An invalid or unknown setting prints a warning with file and line and falls back to the default. [docs]

**`.wslconfig` does not apply to WSL containers.** It configures the VM used by WSL distributions; the container session is sized only by `settings.yaml` (CLI) or by `SessionSettings` in code (API). The two VMs are separate, so their memory ceilings add up: by default a distro VM and a container session can each take up to half of RAM. [docs]

## How it differs from Docker Desktop

| Topic | Docker Desktop | WSL containers |
|---|---|---|
| Engine lifetime | Long-running VM and daemon | VM per session, on demand, gone after 30 idle seconds |
| Idle memory | Resident while running | None once the session has shut down |
| Control channel | Docker API over a named pipe | COM to the WSL service; no Docker API on the host |
| Image store | Its own | Per session, per user, per elevation level |
| Host files | 9p or gRPC-FUSE | VirtioFS |
| Published ports | All interfaces by default | Loopback by default |
| Network | NAT with its own proxy settings | Relayed through Windows; inherits VPN and proxy |
| Orchestration | Compose, Kubernetes | Neither yet |
| Licensing and install | Separate product | Part of WSL, updated by `wsl --update` |

## Not documented

Say "not documented" for these instead of inferring: Windows edition and hardware requirements specific to containers, ARM64 support status, the exact kernel version, per-container default memory or PID limits, seccomp and AppArmor profiles in use, whether user namespaces or rootless mode are available, image signature verification, and any formal statement of the container-to-host threat model beyond the security document quoted above.
