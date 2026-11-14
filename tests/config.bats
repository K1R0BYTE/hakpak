#!/usr/bin/env bats
# Tests for config linking (link_config) and the history merge
# (merge_history) in install/lib.sh. These use the real adapter against a
# temp $HOME and a temp system root, so nothing outside the test dir changes.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_SYSROOT="$BATS_TEST_TMPDIR/root"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  mkdir -p "$HOME" "$HAKPAK_SYSROOT/etc" "$HAKPAK_OPT"
  unset HAKPAK_DRY_RUN
  # A sudo stub that just runs the command, so the "not writable" path can
  # be exercised without root.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "sudo $*" >> "%s/sudo.log"\nexec "$@"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/sudo"
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

lib() {
  # shellcheck source=/dev/null
  source "$REPO/install/lib.sh"
}

# --- link_config: home dotfiles are symlinked ---

@test "link_config backs up a real file and links the config" {
  echo original > "$HOME/.zshrc"
  lib
  link_config zsh/.zshrc "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$REPO/configs/zsh/.zshrc" ]
  [ "$(cat "$HOME/.zshrc.bak")" = "original" ]
}

@test "link_config links when nothing is there yet, without a backup" {
  lib
  link_config tmux/.tmux.conf "$HOME/.tmux.conf"
  [ "$(readlink "$HOME/.tmux.conf")" = "$REPO/configs/tmux/.tmux.conf" ]
  [ ! -e "$HOME/.tmux.conf.bak" ]
}

@test "link_config a second time is a no-op" {
  echo original > "$HOME/.zshrc"
  lib
  link_config zsh/.zshrc "$HOME/.zshrc"
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/second.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  run link_config zsh/.zshrc "$HOME/.zshrc"
  [ "$status" -eq 0 ]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
  [ "$(cat "$HOME/.zshrc.bak")" = "original" ]
}

@test "link_config never overwrites an earlier backup" {
  echo original > "$HOME/.zshrc"
  echo older > "$HOME/.zshrc.bak"
  lib
  link_config zsh/.zshrc "$HOME/.zshrc"
  [ "$(cat "$HOME/.zshrc.bak")" = "older" ]
  # the real file is still kept, next to the first backup
  grep -qx original "$HOME"/.zshrc.bak.*
  [ "$(readlink "$HOME/.zshrc")" = "$REPO/configs/zsh/.zshrc" ]
}

@test "link_config replaces a stale link without backing it up" {
  ln -s /nonexistent/.hakpak/configs/zsh/.zshrc "$HOME/.zshrc"
  lib
  link_config zsh/.zshrc "$HOME/.zshrc"
  [ "$(readlink "$HOME/.zshrc")" = "$REPO/configs/zsh/.zshrc" ]
  [ ! -e "$HOME/.zshrc.bak" ] && [ ! -L "$HOME/.zshrc.bak" ]
}

@test "link_config fails for a config that isn't in configs/" {
  lib
  run link_config zsh/nope "$HOME/.nope"
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.nope" ] && [ ! -L "$HOME/.nope" ]
}

@test "link_config refuses a path that leaves configs/" {
  lib
  run link_config ../install/lib.sh "$HOME/.evil"
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.evil" ] && [ ! -L "$HOME/.evil" ]
}

@test "link_config uses sudo when the target dir isn't writable" {
  [ "$(id -u)" -ne 0 ] || skip "root can write anywhere"
  mkdir -p "$HOME/ro"
  chmod 555 "$HOME/ro"
  lib
  link_config zsh/.zshrc "$HOME/ro/.zshrc" || true
  chmod 755 "$HOME/ro"
  grep -q "sudo ln" "$BATS_TEST_TMPDIR/sudo.log"
}

@test "link_config doesn't use sudo when the target dir is writable" {
  lib
  link_config zsh/.zshrc "$HOME/.zshrc"
  [ ! -e "$BATS_TEST_TMPDIR/sudo.log" ]
}

@test "link_config in dry run changes nothing" {
  echo original > "$HOME/.zshrc"
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  lib
  link_config zsh/.zshrc "$HOME/.zshrc"
  [ "$(cat "$HOME/.zshrc")" = "original" ]
  grep -q "ln -sfn $REPO/configs/zsh/.zshrc $HOME/.zshrc" "$HAKPAK_DRY_RUN_LOG"
}

# --- link_config: files under /etc are copied ---

@test "link_config copies a config under /etc with mode 644, backing up the original" {
  echo original > "$HAKPAK_SYSROOT/etc/wsl.conf"
  lib
  link_config wsl.conf /etc/wsl.conf
  t="$HAKPAK_SYSROOT/etc/wsl.conf"
  [ ! -L "$t" ]
  cmp -s "$REPO/configs/wsl.conf" "$t"
  [ "$(stat -c %a "$t")" = "644" ]
  [ "$(cat "$t.bak")" = "original" ]
}

@test "link_config for /etc a second time is a no-op" {
  echo original > "$HAKPAK_SYSROOT/etc/wsl.conf"
  lib
  link_config wsl.conf /etc/wsl.conf
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/second.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  run link_config wsl.conf /etc/wsl.conf
  [ "$status" -eq 0 ]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
  [ "$(cat "$HAKPAK_SYSROOT/etc/wsl.conf.bak")" = "original" ]
}

@test "link_config for /etc updates a changed copy, keeping the first backup and your edits" {
  echo original > "$HAKPAK_SYSROOT/etc/wsl.conf"
  lib
  link_config wsl.conf /etc/wsl.conf
  echo edited > "$HAKPAK_SYSROOT/etc/wsl.conf"
  link_config wsl.conf /etc/wsl.conf
  cmp -s "$REPO/configs/wsl.conf" "$HAKPAK_SYSROOT/etc/wsl.conf"
  [ "$(cat "$HAKPAK_SYSROOT/etc/wsl.conf.bak")" = "original" ]
  grep -qx edited "$HAKPAK_SYSROOT"/etc/wsl.conf.bak.*
}

@test "link_config for /etc replaces an old symlink into the repo with a copy" {
  ln -s "$REPO/configs/wsl.conf" "$HAKPAK_SYSROOT/etc/wsl.conf"
  lib
  link_config wsl.conf /etc/wsl.conf
  [ ! -L "$HAKPAK_SYSROOT/etc/wsl.conf" ]
  cmp -s "$REPO/configs/wsl.conf" "$HAKPAK_SYSROOT/etc/wsl.conf"
  [ ! -e "$HAKPAK_SYSROOT/etc/wsl.conf.bak" ]
}

# --- merge_history ---

@test "merge_history keeps existing history and adds the curated entries" {
  printf ': 1700000000:0;ls -la\n: 1700000001:0;whoami\n' > "$HOME/.zsh_history"
  lib
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  h="$HOME/.zsh_history"
  [ ! -L "$h" ]
  grep -qxF ': 1700000000:0;ls -la' "$h"
  grep -qxF ': 1700000001:0;whoami' "$h"
  # every curated entry is there
  while IFS= read -r line; do
    grep -qxF -- "$line" "$h" || { echo "missing: $line"; return 1; }
  done < "$REPO/configs/zsh/.zsh_history"
  # your own commands stay last, so Ctrl+R finds them first
  [ "$(tail -n1 "$h")" = ': 1700000001:0;whoami' ]
}

@test "merge_history adds no duplicates, on a re-run or for a command you already have" {
  first="$(head -n1 "$REPO/configs/zsh/.zsh_history")"
  cmd="${first#*;}"
  printf ': 1700000000:0;%s\n' "$cmd" > "$HOME/.zsh_history"
  lib
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  [ "$(grep -cF -- ";$cmd" "$HOME/.zsh_history")" -eq 1 ]
  [ "$(sort "$HOME/.zsh_history" | uniq -d | wc -l)" -eq 0 ]
}

@test "merge_history creates a private history file when there is none" {
  lib
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  # same entries, ending in a newline (the curated file has none)
  diff <(sed -e '$a\' "$REPO/configs/zsh/.zsh_history") "$HOME/.zsh_history"
  [ "$(stat -c %a "$HOME/.zsh_history")" = "600" ]
}

@test "merge_history turns an old symlink into the repo into your own file" {
  # A copy of the repo, so the test can't touch the real tracked file.
  cp -r "$REPO/install" "$REPO/configs" "$BATS_TEST_TMPDIR/"
  REPO="$BATS_TEST_TMPDIR"
  tracked="$REPO/configs/zsh/.zsh_history"
  { sed -e '$a\' "$tracked"; echo ': 1700000002:0;typed-before'; } > "$tracked.new" && mv "$tracked.new" "$tracked"
  ln -s "$tracked" "$HOME/.zsh_history"
  lib
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  [ ! -L "$HOME/.zsh_history" ]
  grep -qxF ': 1700000002:0;typed-before' "$HOME/.zsh_history"
  [ "$(tail -n1 "$tracked")" = ': 1700000002:0;typed-before' ]
}

@test "merge_history writes through your own link to somewhere else" {
  mkdir -p "$HOME/sync"
  echo ': 1700000000:0;mine' > "$HOME/sync/history"
  ln -s "$HOME/sync/history" "$HOME/.zsh_history"
  lib
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  [ "$(readlink "$HOME/.zsh_history")" = "$HOME/sync/history" ]
  [ "$(tail -n1 "$HOME/sync/history")" = ': 1700000000:0;mine' ]
  [ "$(wc -l < "$HOME/sync/history")" -gt 1 ]
}

@test "merge_history keeps a multi-line entry together" {
  printf ': 1700000000:0;for i in 1 2; do\\\necho $i\\\ndone\n' > "$HOME/.zsh_history"
  lib
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  [ "$(grep -c '^echo \$i\\$' "$HOME/.zsh_history")" -eq 1 ]
  [ "$(tail -n3 "$HOME/.zsh_history" | head -n1)" = ': 1700000000:0;for i in 1 2; do\' ]
}

@test "merge_history in dry run changes nothing" {
  echo ': 1700000000:0;ls' > "$HOME/.zsh_history"
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/dry.log"
  lib
  merge_history zsh/.zsh_history "$HOME/.zsh_history"
  [ "$(cat "$HOME/.zsh_history")" = ': 1700000000:0;ls' ]
  [ -s "$HAKPAK_DRY_RUN_LOG" ]
}

# --- call sites ---

section() {
  grep -q 'lib.sh' "$REPO/install/$1" || { echo "$1 does not source lib.sh"; return 1; }
  export HAKPAK_DRY_RUN=1 HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  : > "$HAKPAK_DRY_RUN_LOG"
  run bash "$REPO/install/$1"
}

@test "top section links its dotfiles with link_config and merges history" {
  grep -q '^step .zshrc link_config zsh/.zshrc' "$REPO/install/top.sh"
  grep -q '^step .dircolors link_config .dircolors' "$REPO/install/top.sh"
  grep -q '^step .tmux.conf link_config tmux/.tmux.conf' "$REPO/install/top.sh"
  grep -q '^step .zsh_history merge_history zsh/.zsh_history' "$REPO/install/top.sh"
  ! grep -q '_link_home_config' "$REPO/install/top.sh"
}

@test "top section never symlinks .zsh_history into the repo" {
  section top.sh
  grep -q "ln -sfn $REPO/configs/zsh/.zshrc $HOME/.zshrc" "$HAKPAK_DRY_RUN_LOG"
  grep -q "_merge_history_into $REPO/configs/zsh/.zsh_history $HOME/.zsh_history" "$HAKPAK_DRY_RUN_LOG"
  ! grep -q "ln .*configs/zsh/.zsh_history" "$HAKPAK_DRY_RUN_LOG"
}

@test "rdp section leaves wsl.conf to the wsl section" {
  section rdp.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  if grep -q "wsl.conf" "$HAKPAK_DRY_RUN_LOG"; then return 1; fi
}

@test "rdp section on WSL without systemd points to the wsl section" {
  mkdir -p "$HAKPAK_SYSROOT/proc/sys/kernel"
  echo 6.6.87.2-microsoft-standard-WSL2 > "$HAKPAK_SYSROOT/proc/sys/kernel/osrelease"
  section rdp.sh
  [[ "$output" == *"wsl section"* ]] || { echo "$output"; return 1; }
  cp "$REPO/configs/wsl.conf" "$HAKPAK_SYSROOT/etc/wsl.conf"
  section rdp.sh
  [[ "$output" != *"wsl section"* ]] || { echo "$output"; return 1; }
  printf '[boot]\nsystemd = true\n' > "$HAKPAK_SYSROOT/etc/wsl.conf"
  section rdp.sh
  [[ "$output" != *"wsl section"* ]] || { echo "$output"; return 1; }
}

@test "wsl.conf turns on systemd and turns off automount and interop" {
  c="$REPO/configs/wsl.conf"
  grep -qx 'systemd=true' "$c"
  diff <(grep -v '^$' "$c") - <<'EOF'
[boot]
systemd=true
[automount]
enabled=false
mountFsTab=false
[interop]
enabled=false
appendWindowsPath=false
EOF
}

@test "rdp section uses systemctl, not /etc/init.d" {
  section rdp.sh
  ! grep -q '/etc/init.d' "$REPO/install/rdp.sh"
  grep -q "systemctl enable xrdp" "$HAKPAK_DRY_RUN_LOG"
}

@test "rdp aliases use systemctl" {
  grep -q "startrdp='sudo systemctl start xrdp'" "$REPO/system/.alias"
  grep -q "stoprdp='sudo systemctl stop xrdp'" "$REPO/system/.alias"
  ! grep -q 'service xrdp' "$REPO/system/.alias"
}

@test "rdp section backs up xrdp.ini only once and anchors its edits" {
  section rdp.sh
  grep -q 'cp -p /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.bak' "$HAKPAK_DRY_RUN_LOG"
  grep -q 'if \[ ! -e /etc/xrdp/xrdp.ini.bak \]' "$REPO/install/rdp.sh"
  ! grep -q 's/max_bpp=32/#max_bpp' "$REPO/install/rdp.sh"
}

@test "xrdp.ini edits are idempotent" {
  cat > "$BATS_TEST_TMPDIR/xrdp.ini" <<'EOF'
[Globals]
port=3389
max_bpp=32
[Xvnc]
#xserverbpp=24
EOF
  expr="$(grep -o "s/^port=3389.*'" "$REPO/install/rdp.sh" | head -n1)"
  expr="${expr%\'}"
  [ -n "$expr" ]
  sed -i -E "$expr" "$BATS_TEST_TMPDIR/xrdp.ini"
  cp "$BATS_TEST_TMPDIR/xrdp.ini" "$BATS_TEST_TMPDIR/once.ini"
  sed -i -E "$expr" "$BATS_TEST_TMPDIR/xrdp.ini"
  cmp -s "$BATS_TEST_TMPDIR/once.ini" "$BATS_TEST_TMPDIR/xrdp.ini"
  grep -qx 'port=3390' "$BATS_TEST_TMPDIR/xrdp.ini"
  grep -qx 'max_bpp=128' "$BATS_TEST_TMPDIR/xrdp.ini"
  grep -qx 'xserverbpp=128' "$BATS_TEST_TMPDIR/xrdp.ini"
}
