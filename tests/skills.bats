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
