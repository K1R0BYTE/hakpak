#!/usr/bin/env bats
# Tests for tools/setup-router, through the dry-run adapter.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HAKPAK_DRY_RUN=1
  export HAKPAK_DRY_RUN_LOG="$BATS_TEST_TMPDIR/commands.log"
  export HAKPAK_ROUTER_STATE="$BATS_TEST_TMPDIR/router.env"
  : > "$HAKPAK_DRY_RUN_LOG"
}

router() {
  run bash "$REPO/tools/setup-router" "$@" < /dev/null
}

recorded() {
  grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG" || {
    echo "expected: $1"; echo "--- recorded:"; cat "$HAKPAK_DRY_RUN_LOG"; return 1
  }
}

not_recorded() {
  if grep -qF -- "$1" "$HAKPAK_DRY_RUN_LOG"; then
    echo "did not expect: $1"; cat "$HAKPAK_DRY_RUN_LOG"; return 1
  fi
}

@test "defaults: wlan0 clients out through eth0, 80 and 443 to localhost:8080" {
  router
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  recorded "sysctl -w net.ipv4.ip_forward=1"
  recorded "iptables -t nat -A POSTROUTING -o eth0 -m comment --comment hakpak -j MASQUERADE"
  recorded "iptables -A FORWARD -i wlan0 -o eth0 -m comment --comment hakpak -j ACCEPT"
  recorded "iptables -A FORWARD -i eth0 -o wlan0 -m conntrack --ctstate RELATED\\,ESTABLISHED -m comment --comment hakpak -j ACCEPT"
  recorded "iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 80 -m comment --comment hakpak -j REDIRECT --to-ports 8080"
  recorded "iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 443 -m comment --comment hakpak -j REDIRECT --to-ports 8080"
}

@test "interfaces, ports and target can be chosen" {
  router --in wlan1 --out eth1 --ports 80,8000 --to 127.0.0.1:9090
  [ "$status" -eq 0 ]
  recorded "-o eth1 -m comment --comment hakpak -j MASQUERADE"
  recorded "-i wlan1 -p tcp --dport 8000 -m comment --comment hakpak -j REDIRECT --to-ports 9090"
  not_recorded "--dport 443"
}

@test "a remote target uses DNAT" {
  router -t 192.168.1.50:8080
  [ "$status" -eq 0 ]
  recorded "-i wlan0 -p tcp --dport 80 -m comment --comment hakpak -j DNAT --to-destination 192.168.1.50:8080"
  not_recorded "REDIRECT"
}

@test "--no-redirect sets up NAT only" {
  router --no-redirect
  [ "$status" -eq 0 ]
  recorded "MASQUERADE"
  not_recorded "PREROUTING"
}

@test "--ap gives the in interface an address and starts hostapd and dnsmasq" {
  router --ap
  [ "$status" -eq 0 ]
  recorded "ip addr add 10.0.0.1/24 dev wlan0"
  recorded "hostapd -B -P /run/hakpak-hostapd.pid -i wlan0 $REPO/configs/mitm/hostapd.conf"
  recorded "dnsmasq -C $REPO/configs/mitm/dnsmasq.conf --interface=wlan0"
}

@test "without --ap the in interface address is left alone" {
  router
  not_recorded "ip addr"
  not_recorded "hostapd"
}

@test "--down removes the rules it added and restores forwarding" {
  cat > "$HAKPAK_ROUTER_STATE" <<STATE
IN=wlan1
OUT=eth1
PORTS=8443
TO=127.0.0.1:8080
TO_HOST=127.0.0.1
TO_PORT=8080
REDIRECT=1
RULES_ADDED=1
FORWARD_CHANGED=1
OLD_FORWARD=0
STATE
  router --down
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  recorded "iptables -t nat -D POSTROUTING -o eth1 -m comment --comment hakpak -j MASQUERADE"
  recorded "iptables -t nat -D PREROUTING -i wlan1 -p tcp --dport 8443 -m comment --comment hakpak -j REDIRECT --to-ports 8080"
  recorded "sysctl -w net.ipv4.ip_forward=0"
  not_recorded "ip addr del"
  not_recorded "nmcli"
}

@test "dry run doesn't write the state file" {
  router
  [ ! -e "$HAKPAK_ROUTER_STATE" ]
}

@test "an option missing its value is an error, not a hang" {
  run timeout 5 bash "$REPO/tools/setup-router" -i
  [ "$status" -ne 0 ] && [ "$status" -ne 124 ]
  [[ "$output" == *"needs a value"* ]]
}

@test "redirecting 443 blocks QUIC so browsers fall back to TCP" {
  router
  recorded "iptables -A FORWARD -i wlan0 -p udp --dport 443 -m comment --comment hakpak -j REJECT"
}

@test "QUIC isn't blocked when 443 isn't redirected" {
  router -p 80
  not_recorded "udp"
}

@test "a hostname target is rejected (DNAT needs an IP)" {
  router -t proxybox:8080
  [ "$status" -ne 0 ]
}

@test "an out-of-range target port is rejected" {
  router -t 127.0.0.1:99999
  [ "$status" -ne 0 ]
}

@test "a failing step undoes what was done and reports failure" {
  unset HAKPAK_DRY_RUN
  stubs="$BATS_TEST_TMPDIR/bin"; mkdir -p "$stubs"
  calls="$BATS_TEST_TMPDIR/calls"
  for c in sysctl ip nmcli hostapd dnsmasq kill; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$calls" > "$stubs/$c"
  done
  # iptables: the first two rules work, the third fails
  printf '#!/bin/sh\necho "iptables $*" >> "%s"\nn=$(grep -c "^iptables .* -A " "%s")\n[ "$n" -ge 3 ] && exit 1\nexit 0\n' "$calls" "$calls" > "$stubs/iptables"
  chmod +x "$stubs"/*
  PATH="$stubs:$PATH" _HAKPAK_EUID=0 run bash "$REPO/tools/setup-router" < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" != *"now go to"* ]]
  grep -q "iptables -t nat -D POSTROUTING -o eth0" "$calls"
  grep -q "sysctl -w net.ipv4.ip_forward=" "$calls"
  [ ! -e "$HAKPAK_ROUTER_STATE" ]
}

@test "--down with nothing set up says so" {
  router --down
  [ "$status" -ne 0 ]
  [[ "$output" == *"No router"* ]]
}

@test "bad port list is rejected" {
  router -p 80,http
  [ "$status" -ne 0 ]
  [[ "$output" == *"port"* ]]
}

@test "bad target is rejected" {
  router -t localhost
  [ "$status" -ne 0 ]
  [[ "$output" == *"HOST:PORT"* ]]
}

@test "same in and out interface is rejected" {
  router -i eth0 -o eth0
  [ "$status" -ne 0 ]
}

@test "needs root outside dry run" {
  [ "$(id -u)" -ne 0 ] || skip "running as root"
  unset HAKPAK_DRY_RUN
  router
  [ "$status" -ne 0 ]
  [[ "$output" == *"sudo"* ]]
}

@test "--help explains the options" {
  router --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--in"* ]]
  [[ "$output" == *"--down"* ]]
}

@test "sample configs match the router defaults" {
  grep -q '^interface=wlan0' "$REPO/configs/mitm/hostapd.conf"
  grep -q '^ssid=' "$REPO/configs/mitm/hostapd.conf"
  grep -q '^dhcp-range=10.0.0.' "$REPO/configs/mitm/dnsmasq.conf"
  grep -q '^dhcp-option=option:router,10.0.0.1' "$REPO/configs/mitm/dnsmasq.conf"
  ! grep -q '^interface=' "$REPO/configs/mitm/dnsmasq.conf"
}

@test "setup-router alias exists" {
  grep -q "setup-router=" "$REPO/system/.alias"
}

@test "sample AP is WPA2 with the hacktheplanet password, on 802.11n settings most adapters support" {
  c="$REPO/configs/mitm/hostapd.conf"
  grep -qx 'wpa=2' "$c"
  grep -qx 'wpa_key_mgmt=WPA-PSK' "$c"
  grep -qx 'rsn_pairwise=CCMP' "$c"
  grep -qx 'wpa_passphrase=hacktheplanet' "$c"
  grep -qx 'hw_mode=g' "$c"
  grep -qx 'channel=6' "$c"
  grep -qx 'ieee80211n=1' "$c"
  grep -qx 'wmm_enabled=1' "$c"
  ! grep -q '^ht_capab=' "$c"
  ! grep -qE '^(ieee80211ac|ieee80211ax)=1' "$c"
  ! grep -q '^wpa_key_mgmt=.*SAE' "$c"
}

@test "--ap stops early with a clear message when the card can't do AP mode" {
  unset HAKPAK_DRY_RUN
  stubs="$BATS_TEST_TMPDIR/bin"; mkdir -p "$stubs"
  calls="$BATS_TEST_TMPDIR/calls"
  for c in sysctl ip nmcli hostapd dnsmasq iptables; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$calls" > "$stubs/$c"
  done
  cat > "$stubs/iw" <<'IW'
#!/bin/sh
case "$*" in
  "dev wlan0 info") echo "Interface wlan0"; echo "	wiphy 0" ;;
  "phy phy0 info") printf 'Supported interface modes:\n\t * managed\n\t * monitor\nBand 1:\n' ;;
esac
IW
  chmod +x "$stubs"/*
  PATH="$stubs:$PATH" _HAKPAK_EUID=0 run bash "$REPO/tools/setup-router" --ap < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"AP mode"* ]]
  ! grep -q "^hostapd" "$calls" 2>/dev/null
}

@test "mitm section installs iw for the AP check" {
  run bash "$REPO/install/mitm.sh"
  grep -qF "hostapd dnsmasq-base iptables tcpdump iw" "$HAKPAK_DRY_RUN_LOG"
}
