#!/usr/bin/env bats
# Tests for the Toolset manifest (install/toolset.txt): it parses, every
# kind and section is known, every custom function exists, sections install
# from it, and the README tool list is generated from it.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HAKPAK_OPT" "$HOME"
  : > "$HAKPAK_DRY_RUN_LOG"
}

lib() {
  # shellcheck source=/dev/null
  source "$REPO/install/lib.sh"
}

manifest() {
  export HAKPAK_TOOLSET="$BATS_TEST_TMPDIR/toolset.txt"
  cat > "$HAKPAK_TOOLSET"
}

recorded() {
  grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG" || {
    echo "expected command containing: $1"
    echo "--- recorded:"
    cat "$HAKPAK_DRY_RUN_LOG"
    return 1
  }
}

not_recorded() {
  if grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG"; then
    echo "did not expect: $1"
    cat "$HAKPAK_DRY_RUN_LOG"
    return 1
  fi
}

# --- the committed manifest ---

@test "the committed manifest parses and passes every check" {
  lib
  run toolset_check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "every kind in the manifest is one install_tool knows" {
  lib
  [ -n "$(toolset_rows)" ]
  while IFS=$'\t' read -r _ kind _; do
    case "$kind" in
      apt|go|pipx|gem|git|venv|url|uv|plugin|custom) ;;
      *) echo "unknown kind: $kind"; return 1 ;;
    esac
  done < <(toolset_rows)
}

@test "every custom function in the manifest exists" {
  lib
  toolset_rows | cut -f2 | grep -qx custom
  while IFS=$'\t' read -r _ kind name args _; do
    [ "$kind" = custom ] || continue
    declare -F "$args" >/dev/null || { echo "$name: no function $args"; return 1; }
  done < <(toolset_rows)
}

@test "every section has tools and a script that installs it from the manifest" {
  lib
  [ "${#HAKPAK_SECTIONS[@]}" -gt 0 ]
  for s in "${HAKPAK_SECTIONS[@]}"; do
    id="${s%%:*}"
    [ "$id" = wsl ] && continue  # config only: /etc/wsl.conf, no tools
    [ -n "$(toolset_rows "$id")" ] || { echo "$id has no tools"; return 1; }
    grep -q "^install_section $id\$" "$REPO"/install/*.sh || { echo "no script runs install_section $id"; return 1; }
  done
}

@test "no tool is listed twice in one section" {
  lib
  [ -n "$(toolset_rows)" ]
  dups="$(toolset_rows | cut -f1,3 | sort | uniq -d)"
  [ -z "$dups" ] || { echo "listed twice: $dups"; return 1; }
}

@test "a tool listed in two sections has the same row in both" {
  lib
  # kind, name and source (fields 2-4) of every row: one distinct row per name.
  differ="$(toolset_rows | cut -f2-4 | sort -u | cut -f2 | sort | uniq -d)"
  [ -z "$differ" ] || { echo "different rows for: $differ"; return 1; }
}

# --- parsing and checks ---

@test "rows give section, kind, name, source and the note" {
  manifest <<'EOF'
# a comment line

web   go    ffuf  github.com/ffuf/ffuf/v2@latest
basic apt   fzf                                  # Ctrl+R history search
EOF
  lib
  run toolset_rows
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'web\tgo\tffuf\tgithub.com/ffuf/ffuf/v2@latest\t' ]
  [ "${lines[1]}" = $'basic\tapt\tfzf\t\tCtrl+R history search' ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "rows can be filtered by section" {
  manifest <<'EOF'
web   apt  whatweb
mitm  apt  hostapd
web   apt  wfuzz
EOF
  lib
  run toolset_rows web
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *whatweb* ]]
  [[ "${lines[1]}" == *wfuzz* ]]
}

@test "check reports an unknown kind" {
  manifest <<'EOF'
web  brew  ffuf
EOF
  lib
  run toolset_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 1"*"unknown kind: brew"* ]]
}

@test "check reports an unknown section" {
  manifest <<'EOF'
clouds  apt  awscli
EOF
  lib
  run toolset_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown section: clouds"* ]]
}

@test "check reports a custom tool whose function doesn't exist" {
  manifest <<'EOF'
web  custom  thing  _install_no_such_thing
EOF
  lib
  run toolset_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"no function _install_no_such_thing"* ]]
}

@test "check reports a missing source for kinds that need one" {
  manifest <<'EOF'
web  go   ffuf
web  git  nikto
web  url  linpeas  https://example.test/linpeas.sh
EOF
  lib
  run toolset_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"ffuf"*"needs"* ]]
  [[ "$output" == *"nikto"*"needs"* ]]
  [[ "$output" == *"linpeas"*"needs"* ]]
}

@test "check reports a tool listed twice in one section" {
  manifest <<'EOF'
web      go  gospider  github.com/jaeles-project/gospider@latest
pentest  apt nmap
web      go  gospider  github.com/jaeles-project/gospider@latest
EOF
  lib
  run toolset_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 3: gospider listed twice in web (also line 1)"* ]] || { echo "$output"; return 1; }
}

@test "check allows the same tool in two sections" {
  manifest <<'EOF'
web      go  gospider  github.com/jaeles-project/gospider@latest  # crawler
pentest  go  gospider  github.com/jaeles-project/gospider@latest
web      apt nmap
pentest  apt nmap
EOF
  lib
  run toolset_check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "check reports a tool that two sections install in different ways" {
  manifest <<'EOF'
web      go   gospider  github.com/jaeles-project/gospider@latest
pentest  go   gospider  github.com/jaeles-project/gospider@v1.0.0
web      apt  nmap
pentest  pipx nmap
EOF
  lib
  run toolset_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 2: gospider: not the same as in web (line 1)"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"line 4: nmap: not the same as in web (line 3)"* ]] || { echo "$output"; return 1; }
}

@test "check reports a row with no name" {
  manifest <<'EOF'
web  apt
EOF
  lib
  run toolset_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 1"* ]]
}

# --- installing a section from the manifest ---

@test "install_section installs each tool of the section and only those" {
  manifest <<'EOF'
web   apt  whatweb
mitm  apt  hostapd
web   go   ffuf  github.com/ffuf/ffuf/v2@latest
EOF
  lib
  install_section web
  recorded "apt-get install -y whatweb"
  recorded "go install -v github.com/ffuf/ffuf/v2@latest"
  ! grep -q hostapd "$HAKPAK_DRY_RUN_LOG"
}

@test "install_section passes every source field and expands \$HOME and \$HAKPAK_OPT" {
  manifest <<'EOF'
basic      git  tpm       https://github.com/tmux-plugins/tpm  $HOME/.tmux/plugins/tpm
wordlists  git  seclists  https://github.com/danielmiessler/SecLists  $HAKPAK_OPT/wordlists/seclists
EOF
  lib
  install_section basic
  install_section wordlists
  recorded "git clone --depth 1 https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm"
  recorded "git clone --depth 1 https://github.com/danielmiessler/SecLists $HAKPAK_OPT/wordlists/seclists"
}

@test "install_section doesn't expand anything else in a row" {
  manifest <<'EOF'
web  pipx  thing  $(id)$PATH
EOF
  lib
  install_section web
  recorded 'pipx install \$\(id\)\$PATH'
}

@test "install_section keeps going when one tool fails" {
  manifest <<'EOF'
web  custom  broken  _test_broken
web  apt     wfuzz
EOF
  lib
  _test_broken() { return 1; }
  run install_section web
  recorded "apt-get install -y wfuzz"
}

@test "install_section refuses a broken manifest" {
  manifest <<'EOF'
web  brew  ffuf
EOF
  lib
  run install_section web
  [ "$status" -eq 1 ]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
}

# --- README generated from the manifest ---

@test "the README tool list matches the manifest" {
  run "$REPO/tools/gen-readme" --check
  [ "$status" -eq 0 ] || { echo "$output"; echo "run tools/gen-readme to update README.md"; return 1; }
}

@test "gen-readme renders sections in order with kinds and notes" {
  manifest <<'EOF'
web    pipx    sqlmap
basic  apt     fzf                       # Ctrl+R history search
web    custom  nikto   _install_nikto    # git, with a link in /usr/local/bin
EOF
  run "$REPO/tools/gen-readme" --print
  [ "$status" -eq 0 ]
  expected="## Basic

* fzf (apt): Ctrl+R history search

## Web Tools

* sqlmap (pipx)
* nikto: git, with a link in /usr/local/bin"
  [ "$output" = "$expected" ] || { echo "$output"; return 1; }
}

@test "gen-readme --check fails when the README is out of date" {
  manifest <<'EOF'
web  pipx  sqlmap
EOF
  run "$REPO/tools/gen-readme" --check
  [ "$status" -ne 0 ]
}

@test "gen-readme writes the tool list between the markers and keeps the rest" {
  manifest <<'EOF'
web  pipx  sqlmap
EOF
  export HAKPAK_README="$BATS_TEST_TMPDIR/README.md"
  printf 'intro\n<!-- toolset:start -->\nold\n<!-- toolset:end -->\noutro\n' > "$HAKPAK_README"
  run "$REPO/tools/gen-readme"
  [ "$status" -eq 0 ]
  [ "$(cat "$HAKPAK_README")" = "intro
<!-- toolset:start -->
## Web Tools

* sqlmap (pipx)
<!-- toolset:end -->
outro" ]
  run "$REPO/tools/gen-readme" --check
  [ "$status" -eq 0 ]
}

@test "README no longer says it's for Kali only" {
  ! grep -qi 'kali only\|kali-only\|only kali' "$REPO/README.md"
}

# --- review fixes ---

@test "a broken manifest makes the section fail its summary" {
  manifest <<'EOF2'
web  brew  ffuf
EOF2
  lib
  install_section web || true
  run install_summary
  [ "$status" -ne 0 ]
}

@test "install_section fails on a section with no tools" {
  manifest <<'EOF2'
web  apt  wfuzz
EOF2
  lib
  run install_section webb
  [ "$status" -ne 0 ]
  [[ "$output" == *"no tools in section webb"* ]]
}

@test "\$HOME with an & in it expands as is" {
  manifest <<'EOF2'
basic  git  tpm  https://github.com/tmux-plugins/tpm  $HOME/.tmux/plugins/tpm
EOF2
  export HOME="$BATS_TEST_TMPDIR/a&b"
  mkdir -p "$HOME"
  lib
  install_section basic
  grep -qF "a\\&b/.tmux/plugins/tpm" "$HAKPAK_DRY_RUN_LOG" || { cat "$HAKPAK_DRY_RUN_LOG"; return 1; }
}

@test "a section's apt tools install in one apt-get call" {
  manifest <<'EOF2'
mitm  apt   hostapd
mitm  pipx  mitmproxy
mitm  apt   iw
EOF2
  lib
  install_section mitm
  recorded "apt-get install -y hostapd iw"
  [ "$(grep -c 'apt-get install' "$HAKPAK_DRY_RUN_LOG")" -eq 1 ]
}

@test "when the batched apt-get fails, each apt tool is tried on its own and only the bad one fails" {
  manifest <<'EOF2'
mitm  apt  hostapd
mitm  apt  no-such-package
mitm  apt  iw
EOF2
  unset HAKPAK_DRY_RUN
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # sudo stub: log the apt-get call, fail if it names the bad package.
  cat > "$BATS_TEST_TMPDIR/bin/sudo" <<STUB
#!/bin/sh
echo "\$*" >> "$HAKPAK_DRY_RUN_LOG"
case " \$* " in *" no-such-package "*) exit 100 ;; esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  lib
  install_section mitm
  recorded "apt-get install -y hostapd no-such-package iw"
  recorded "apt-get install -y hostapd"
  recorded "apt-get install -y iw"
  [ "${HAKPAK_FAILED[*]}" = "no-such-package" ]
}

@test "a failing oh-my-zsh plugin is reported by its own name" {
  lib
  _install_git() { [ "$1" != zsh-autosuggestions ]; }
  touch_home="$HOME/.oh-my-zsh"; mkdir -p "$touch_home"; touch "$touch_home/oh-my-zsh.sh"
  install_tool custom oh-my-zsh _install_oh_my_zsh || true
  [ "${HAKPAK_FAILED[*]}" = "zsh-autosuggestions" ]
}

# --- oh-my-zsh login shell ---

@test "oh-my-zsh changes the login shell for the user id -un names, even with USER unset" {
  lib
  unset USER
  _login_shell() { echo /bin/bash; }
  install_tool custom oh-my-zsh _install_oh_my_zsh
  grep -qE "^sudo usermod -s [^ ]*zsh $(id -un)\$" "$HAKPAK_DRY_RUN_LOG"
}

@test "oh-my-zsh leaves the login shell alone when it is already zsh" {
  lib
  _login_shell() { echo /usr/bin/zsh; }
  install_tool custom oh-my-zsh _install_oh_my_zsh
  not_recorded "usermod"
}

@test "an installed oh-my-zsh still gets the login shell changed on a re-run" {
  lib
  mkdir -p "$HOME/.oh-my-zsh"; touch "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  _login_shell() { echo /bin/bash; }
  install_tool custom oh-my-zsh _install_oh_my_zsh
  not_recorded "ohmyzsh.git"
  recorded "sudo usermod -s"
}

@test "a failed shell change warns with the manual command and doesn't fail oh-my-zsh" {
  lib
  _login_shell() { echo /bin/bash; }
  run_step() {
    case "$*" in *usermod*) return 1 ;; esac
    echo "$*" >> "$HAKPAK_DRY_RUN_LOG"
  }
  run install_tool custom oh-my-zsh _install_oh_my_zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo usermod -s"*"$(id -un)"* ]]
  [[ "$output" != *"failed: oh-my-zsh"* ]]
  recorded "zsh-autosuggestions"
}

@test "the login shell is never changed with chsh, which can ask for a password even under sudo" {
  lib
  _login_shell() { echo /bin/bash; }
  install_tool custom oh-my-zsh _install_oh_my_zsh
  not_recorded "chsh"
}
