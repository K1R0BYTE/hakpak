#!/usr/bin/env bats
# Checks the agent skills kept in .claude/skills: each one is a directory
# holding a SKILL.md whose frontmatter names the directory and carries a
# description a skill loader will accept. Nothing is installed or run.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILLS="$REPO/.claude/skills"
}

# Prints the value of one frontmatter key from a SKILL.md.
frontmatter() {
  awk -v key="$2" '
    NR == 1 && $0 != "---" { exit 1 }
    NR > 1 && $0 == "---" { exit }
    index($0, key ": ") == 1 { print substr($0, length(key) + 3) }
  ' "$1"
}

@test "skills: sbx-cli and sbx-arch are present" {
  [ -f "$SKILLS/sbx-cli/SKILL.md" ]
  [ -f "$SKILLS/sbx-arch/SKILL.md" ]
}

@test "skills: frontmatter name matches the directory" {
  for file in "$SKILLS"/*/SKILL.md; do
    dir="$(basename "$(dirname "$file")")"
    name="$(frontmatter "$file" name)"
    [ "$name" = "$dir" ] || { echo "$file: name '$name' is not '$dir'"; return 1; }
  done
}

@test "skills: description is set, at most 1024 characters, no angle brackets" {
  for file in "$SKILLS"/*/SKILL.md; do
    description="$(frontmatter "$file" description)"
    [ -n "$description" ] || { echo "$file: no description"; return 1; }
    [ "${#description}" -le 1024 ] || { echo "$file: description is ${#description} characters"; return 1; }
    case "$description" in
      *'<'* | *'>'*) echo "$file: description has an angle bracket"; return 1 ;;
    esac
  done
}

@test "skills: wslc-cli and wslc-arch are present" {
  [ -f "$SKILLS/wslc-cli/SKILL.md" ]
  [ -f "$SKILLS/wslc-arch/SKILL.md" ]
}

@test "skills: wslc-cli and wslc-arch point at each other" {
  grep -q 'wslc-arch' "$SKILLS/wslc-cli/SKILL.md"
  grep -q 'wslc-cli' "$SKILLS/wslc-arch/SKILL.md"
}

@test "skills: wslc skills say they were not run against a live wslc" {
  for file in "$SKILLS"/wslc-cli/SKILL.md "$SKILLS"/wslc-arch/SKILL.md; do
    grep -q 'live `wslc.exe`' "$file" || { echo "$file: no live-run caveat"; return 1; }
  done
}

@test "skills: no command wslc rejects is recommended" {
  # -h is --hostname, not help; host networking and the on-failure and
  # unless-stopped restart policies are refused. Each may appear only on a
  # line that says so.
  for file in "$SKILLS"/wslc-cli/SKILL.md "$SKILLS"/wslc-arch/SKILL.md; do
    if grep -n -e '--network host' "$file" | grep -v -e 'rejected' -e 'Not supported'; then
      echo "$file: recommends --network host"; return 1
    fi
    if grep -n -e 'unless-stopped' "$file" | grep -v -e 'rejected' -e 'Only `no` and `always`'; then
      echo "$file: recommends an unsupported restart policy"; return 1
    fi
    if grep -n -E 'wslc( [a-z]+)* -h( |`|$)' "$file"; then
      echo "$file: uses -h as help"; return 1
    fi
  done
}

@test "skills: sbx-cli and sbx-arch point at each other" {
  grep -q 'sbx-arch' "$SKILLS/sbx-cli/SKILL.md"
  grep -q 'sbx-cli' "$SKILLS/sbx-arch/SKILL.md"
}

@test "skills: no command the installed sbx rejects is recommended" {
  # sbx start does not exist; --detached was renamed to --detach in v0.48.0.
  # Both may be mentioned only on a line that says so.
  for file in "$SKILLS"/sbx-cli/SKILL.md "$SKILLS"/sbx-arch/SKILL.md; do
    if grep -n 'sbx start' "$file" | grep -v 'No such command'; then
      echo "$file: recommends sbx start"; return 1
    fi
    if grep -n -e '--detached' "$file" | grep -v 'is `--detach`'; then
      echo "$file: uses --detached"; return 1
    fi
  done
}

@test "skills: the host LAN address is not called unreachable" {
  # The guidance sbx writes into a sandbox says a host service on a
  # non-loopback address is reachable directly once policy allows it.
  for file in "$SKILLS"/sbx-cli/SKILL.md "$SKILLS"/sbx-arch/SKILL.md; do
    if grep -n -e 'LAN IP do not work' -e 'or the LAN IP\.' "$file"; then
      echo "$file: says the LAN IP cannot be reached"; return 1
    fi
    grep -q 'host.docker.internal' "$file"
  done
}

@test "skills: sbx-cli covers working inside a sandbox" {
  file="$SKILLS/sbx-cli/SKILL.md"
  grep -q '^## Inside the sandbox' "$file"
  for needle in '/etc/sandbox-persistent.sh' 'SANDBOX_NAME' '/run/sandbox/source' \
    'Approval required for' 'Blocked by local rule for' 'Blocked by org policy' \
    'Blocked by network policy' 'DOCKER_SANDBOXES_IP_STACK' '0.0.0.0'; do
    grep -qF -e "$needle" "$file" || { echo "$file: no mention of $needle"; return 1; }
  done
}

@test "skills: sbx-arch covers the guidance sbx writes into a sandbox" {
  file="$SKILLS/sbx-arch/SKILL.md"
  for needle in 'AGENTS.md' 'CLAUDE.md' 'dhi.io' 'apiKeyHelper' 'HTTP 403'; do
    grep -qF -e "$needle" "$file" || { echo "$file: no mention of $needle"; return 1; }
  done
}

@test "skills: the live in-sandbox guidance file is not given authority" {
  # Anything running in a sandbox can rewrite AGENTS.md or CLAUDE.md there.
  for file in "$SKILLS"/sbx-cli/SKILL.md "$SKILLS"/sbx-arch/SKILL.md; do
    if grep -n -e 'prefer it to the docs' -e 'the docs they win' "$file"; then
      echo "$file: ranks the in-sandbox file above the docs"; return 1
    fi
  done
  grep -q 'not as instructions' "$SKILLS/sbx-cli/SKILL.md"
}
