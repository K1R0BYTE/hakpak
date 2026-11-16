#!/usr/bin/env bats
# Tests for the repo's own .gitignore: it covers the global gitignore hakpak
# ships (configs/git/gitignore) and never hides a file the repo tracks.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Only this repo's rules count, not the ignore file of whoever runs the tests.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
}

@test "the repo .gitignore has every pattern of the global gitignore" {
  [ -f "$REPO/.gitignore" ]
  while IFS= read -r pattern; do
    case "$pattern" in '' | '#'*) continue ;; esac
    grep -qxF -- "$pattern" "$REPO/.gitignore" || { echo "missing: $pattern"; return 1; }
  done < "$REPO/configs/git/gitignore"
}

@test "the repo .gitignore hides no tracked file" {
  run git -C "$REPO" ls-files --cached --ignored --exclude-from="$REPO/.gitignore"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the repo .gitignore keeps skills and configs, hides local clutter" {
  cd "$REPO"
  ! git check-ignore -q --no-index .claude/skills/new-skill/SKILL.md
  ! git check-ignore -q --no-index .claude-plugin/marketplace.json
  ! git check-ignore -q --no-index configs/zsh/.zsh_history
  ! git check-ignore -q --no-index configs/new/.env.example
  git check-ignore -q --no-index .claude/settings.local.json
  git check-ignore -q --no-index .env
  git check-ignore -q --no-index tools/__pycache__/x.pyc
  git check-ignore -q --no-index node_modules/x
}
