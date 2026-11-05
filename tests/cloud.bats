#!/usr/bin/env bats
# Tests for the Cloud and CI/CD sections and the helpers they use:
# add_apt_repo, verify_sha256 and verify_gpg_signature (install/lib.sh).
# Section runs go through the dry run; failure paths use the real adapter
# with stub commands first on PATH.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export HAKPAK_OPT="$BATS_TEST_TMPDIR/opt"
  export HAKPAK_SYSROOT="$BATS_TEST_TMPDIR/sysroot"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  mkdir -p "$HOME" "$HAKPAK_OPT" "$HAKPAK_SYSROOT"
  : > "$HAKPAK_DRY_RUN_LOG"
  # A supported distro, so the Azure CLI step doesn't depend on the test host.
  printf 'ID=debian\nVERSION_CODENAME=bookworm\n' > "$BATS_TEST_TMPDIR/os-release"
  export HAKPAK_OS_RELEASE="$BATS_TEST_TMPDIR/os-release"
}

lib() {
  # shellcheck source=/dev/null
  source "$REPO/install/lib.sh"
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

section() {
  grep -q 'lib.sh' "$REPO/install/$1" || { echo "$1 does not source lib.sh"; return 1; }
  run bash "$REPO/install/$1"
}

# Stub commands on PATH for real-adapter tests: stub <name> <script body>
stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Run one custom install as if <command> weren't installed yet, so a test
# doesn't depend on what the test host has (CI runners ship gcloud and az).
install_missing() {
  local cmd="$1"
  shift
  lib
  eval "has_command() { [ \"\$1\" != $cmd ] && command -v \"\$1\" >/dev/null 2>&1; }"
  install_tool "$@"
}

GCLOUD_LINE='deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main'

# --- add_apt_repo ---

@test "add_apt_repo downloads the key, installs the keyring and the source file, and refreshes only that repo" {
  lib
  add_apt_repo google-cloud-sdk https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    /usr/share/keyrings/cloud.google.gpg "$GCLOUD_LINE"
  recorded "curl -fsSL -o"
  recorded "https://packages.cloud.google.com/apt/doc/apt-key.gpg"
  recorded "install -m 644"
  recorded "$HAKPAK_SYSROOT/usr/share/keyrings/cloud.google.gpg"
  recorded "$HAKPAK_SYSROOT/etc/apt/sources.list.d/google-cloud-sdk.list"
  recorded "Dir::Etc::sourcelist=$HAKPAK_SYSROOT/etc/apt/sources.list.d/google-cloud-sdk.list"
  not_recorded "apt-key add"
}

@test "add_apt_repo writes the source line as given" {
  lib
  add_apt_repo google-cloud-sdk https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    /usr/share/keyrings/cloud.google.gpg "$GCLOUD_LINE"
  recorded "$(printf '%q' "$GCLOUD_LINE")"
}

@test "add_apt_repo skips a repo that's already configured" {
  mkdir -p "$HAKPAK_SYSROOT/etc/apt/sources.list.d" "$HAKPAK_SYSROOT/usr/share/keyrings"
  echo "$GCLOUD_LINE" > "$HAKPAK_SYSROOT/etc/apt/sources.list.d/google-cloud-sdk.list"
  echo key > "$HAKPAK_SYSROOT/usr/share/keyrings/cloud.google.gpg"
  lib
  run add_apt_repo google-cloud-sdk https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    /usr/share/keyrings/cloud.google.gpg "$GCLOUD_LINE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already configured"* ]]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ] || { cat "$HAKPAK_DRY_RUN_LOG"; return 1; }
}

@test "add_apt_repo refuses a source line that isn't signed by its keyring" {
  lib
  run add_apt_repo vendor https://example.test/key.asc /usr/share/keyrings/vendor.gpg \
    'deb https://example.test/apt stable main'
  [ "$status" -ne 0 ]
  [[ "$output" == *"signed-by=/usr/share/keyrings/vendor.gpg"* ]]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
}

@test "add_apt_repo refuses a name that isn't a plain file name" {
  lib
  run add_apt_repo ../evil https://example.test/key.asc /usr/share/keyrings/vendor.gpg \
    'deb [signed-by=/usr/share/keyrings/vendor.gpg] https://example.test/apt stable main'
  [ "$status" -ne 0 ]
  [ ! -s "$HAKPAK_DRY_RUN_LOG" ]
}

@test "add_apt_repo removes the source file again when apt can't read the repo" {
  unset HAKPAK_DRY_RUN
  key="$BATS_TEST_TMPDIR/vendor.asc"
  gpg --batch --homedir "$BATS_TEST_TMPDIR/gnupg-src" --quick-gen-key --passphrase '' 'hakpak test <t@example.test>' default default never 2>/dev/null ||
    skip "gpg can't make a test key here"
  gpg --batch --homedir "$BATS_TEST_TMPDIR/gnupg-src" --armor --export > "$key"
  # curl copies the test key; sudo runs apt-get update and fails it.
  stub curl 'while [ $# -gt 1 ]; do [ "$1" = -o ] && cp "'"$key"'" "$2"; shift; done'
  stub sudo 'case "$*" in *apt-get*update*) exit 100 ;; esac; exec "$@"'
  lib
  run add_apt_repo vendor https://example.test/key.asc /usr/share/keyrings/vendor.gpg \
    'deb [signed-by=/usr/share/keyrings/vendor.gpg] https://example.test/apt stable main'
  [ "$status" -ne 0 ]
  [ ! -e "$HAKPAK_SYSROOT/etc/apt/sources.list.d/vendor.list" ]
  [[ "$output" == *"removing"* ]] || { echo "$output"; return 1; }
}

# --- checksums and signatures ---

@test "verify_sha256 passes a file whose hash is in the manifest" {
  lib
  printf 'binary' > "$BATS_TEST_TMPDIR/tool_1.0_linux_amd64"
  ( cd "$BATS_TEST_TMPDIR" && sha256sum tool_1.0_linux_amd64 > sums.txt )
  run verify_sha256 "$BATS_TEST_TMPDIR/tool_1.0_linux_amd64" "$BATS_TEST_TMPDIR/sums.txt" tool_1.0_linux_amd64
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "verify_sha256 fails on a hash mismatch" {
  lib
  printf 'binary' > "$BATS_TEST_TMPDIR/tool"
  echo "0000000000000000000000000000000000000000000000000000000000000000  tool" > "$BATS_TEST_TMPDIR/sums.txt"
  run verify_sha256 "$BATS_TEST_TMPDIR/tool" "$BATS_TEST_TMPDIR/sums.txt" tool
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
}

@test "verify_sha256 fails when the manifest has no entry for the asset" {
  lib
  printf 'binary' > "$BATS_TEST_TMPDIR/tool"
  ( cd "$BATS_TEST_TMPDIR" && sha256sum tool | sed 's/  tool$/  tool.tar.gz/' > sums.txt )
  run verify_sha256 "$BATS_TEST_TMPDIR/tool" "$BATS_TEST_TMPDIR/sums.txt" tool
  [ "$status" -ne 0 ]
  [[ "$output" == *"no checksum"* ]]
}

@test "verify_sha256 reads a file that holds only the hash (kubectl.sha256)" {
  lib
  printf 'binary' > "$BATS_TEST_TMPDIR/kubectl"
  sha256sum "$BATS_TEST_TMPDIR/kubectl" | cut -d' ' -f1 > "$BATS_TEST_TMPDIR/kubectl.sha256"
  run verify_sha256 "$BATS_TEST_TMPDIR/kubectl" "$BATS_TEST_TMPDIR/kubectl.sha256"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf 'other' > "$BATS_TEST_TMPDIR/kubectl"
  run verify_sha256 "$BATS_TEST_TMPDIR/kubectl" "$BATS_TEST_TMPDIR/kubectl.sha256"
  [ "$status" -ne 0 ]
}

@test "the AWS CLI key in the repo is the AWS CLI Team key" {
  run gpg --batch --homedir "$BATS_TEST_TMPDIR" --with-colons --show-keys "$REPO/install/keys/aws-cli.asc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fpr:::::::::FB5DB77FD5C118B80511ADA8A6310ACC4672475C:"* ]] || { echo "$output"; return 1; }
}

@test "verify_gpg_signature fails a file the key didn't sign" {
  lib
  printf 'not the zip' > "$BATS_TEST_TMPDIR/awscliv2.zip"
  printf 'not a signature' > "$BATS_TEST_TMPDIR/awscliv2.zip.sig"
  run verify_gpg_signature "$REPO/install/keys/aws-cli.asc" "$BATS_TEST_TMPDIR/awscliv2.zip.sig" "$BATS_TEST_TMPDIR/awscliv2.zip"
  [ "$status" -ne 0 ]
}

# --- Cloud section ---

@test "cloud section runs cleanly in dry run" {
  section cloud.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "cloud section installs the AWS CLI from AWS's zip and checks its signature" {
  section cloud.sh
  recorded "https://awscli.amazonaws.com/awscli-exe-linux-"
  recorded ".zip.sig"
  recorded "verify_gpg_signature $REPO/install/keys/aws-cli.asc"
  recorded "aws/install"
}

@test "gcloud installs google-cloud-cli from Google's repo with a signed-by keyring" {
  install_missing gcloud custom gcloud _install_gcloud
  recorded "https://packages.cloud.google.com/apt/doc/apt-key.gpg"
  recorded "$(printf '%q' "$GCLOUD_LINE")"
  recorded "apt-get install -y google-cloud-cli"
}

@test "az installs azure-cli from Microsoft's repo for the distro codename" {
  install_missing az custom az _install_azure_cli
  recorded "https://packages.microsoft.com/keys/microsoft.asc"
  recorded "$(printf '%q' 'deb [signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ bookworm main')"
  recorded "apt-get install -y azure-cli"
  not_recorded "aka.ms"
}

@test "cloud section installs kubectl from dl.k8s.io and checks its sha256" {
  section cloud.sh
  recorded "https://dl.k8s.io/release/"
  recorded "/kubectl.sha256"
  recorded "verify_sha256"
  recorded "install -m 755"
  recorded "/usr/local/bin/kubectl"
}

@test "cloud section installs kubescape from its release and checks it" {
  section cloud.sh
  recorded "https://github.com/kubescape/kubescape/releases/download/"
  recorded "checksums.sha256"
  recorded "/usr/local/bin/kubescape"
}

@test "cloud section installs prowler, pacu and gcpwn with pipx" {
  section cloud.sh
  recorded "pipx install prowler"
  recorded "pipx install pacu"
  recorded "pipx install gcpwn"
  not_recorded "sudo pip"
}

@test "azure-cli fails clearly on a codename Microsoft doesn't publish, and the section carries on" {
  unset HAKPAK_DRY_RUN
  printf 'ID=kali\nVERSION_CODENAME=kali-rolling\n' > "$BATS_TEST_TMPDIR/os-release"
  export HAKPAK_OS_RELEASE="$BATS_TEST_TMPDIR/os-release"
  stub curl 'echo "curl $*" >> "'"$HAKPAK_DRY_RUN_LOG"'"; exit 22'
  stub sudo 'echo "sudo $*" >> "'"$HAKPAK_DRY_RUN_LOG"'"; exit 0'
  lib
  has_command() { return 1; }
  run install_tool custom az _install_azure_cli
  [ "$status" -ne 0 ]
  [[ "$output" == *"kali-rolling"* ]] || { echo "$output"; return 1; }
  recorded "repos/azure-cli/dists/kali-rolling/Release"
  not_recorded "sources.list.d"
  not_recorded "install -y azure-cli"
}

@test "azure-cli fails when the distro codename is unknown" {
  printf 'ID=debian\n' > "$BATS_TEST_TMPDIR/os-release"
  export HAKPAK_OS_RELEASE="$BATS_TEST_TMPDIR/os-release"
  lib
  has_command() { return 1; }
  run install_tool custom az _install_azure_cli
  [ "$status" -ne 0 ]
  not_recorded "install -y azure-cli"
}

# --- CI/CD section ---

@test "cicd section runs cleanly in dry run" {
  section cicd.sh
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "cicd section installs trajan with go install and gato-x with pipx" {
  section cicd.sh
  recorded "go install -v github.com/praetorian-inc/trajan/cmd/trajan@latest"
  recorded "pipx install gato-x"
}

@test "cicd section installs trufflehog from its release tarball and checks it" {
  section cicd.sh
  recorded "https://github.com/trufflesecurity/trufflehog/releases/download/"
  recorded "_checksums.txt"
  recorded "verify_sha256"
  recorded "/usr/local/bin/trufflehog"
  not_recorded "go install -v github.com/trufflesecurity"
}

@test "a release tag that isn't a plain version is refused" {
  unset HAKPAK_DRY_RUN
  stub curl 'echo "{\"tag_name\":\"v1.0;rm -rf\"}"'
  lib
  run _github_latest_tag trufflesecurity/trufflehog
  [ "$status" -ne 0 ]
}

@test "the latest release tag is read from GitHub's JSON answer" {
  unset HAKPAK_DRY_RUN
  stub curl 'echo "{\"id\":1,\"tag_name\":\"v3.90.1\",\"update_url\":\"/x\"}"'
  lib
  run _github_latest_tag trufflesecurity/trufflehog
  [ "$status" -eq 0 ]
  [ "$output" = "v3.90.1" ]
}

@test "the AWS CLI install makes sure gpg and gpgv are there before checking the signature" {
  lib
  has_command() { case "$1" in gpg|gpgv) return 1 ;; *) command -v "$1" >/dev/null ;; esac; }
  install_tool custom aws _install_aws_cli
  recorded "apt-get install -y gnupg gpgv"
}
