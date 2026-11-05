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
  recorded "ip addr replace 10.0.0.1/24 dev wlan0"
  recorded "hostapd -B -i wlan0 $REPO/configs/mitm/hostapd.conf"
  recorded "dnsmasq -C $REPO/configs/mitm/dnsmasq.conf --interface=wlan0"
}

@test "without --ap the in interface address is left alone" {
  router
  not_recorded "ip addr"
  not_recorded "hostapd"
}

@test "--down removes the same rules it added and restores forwarding" {
  router -i wlan1 -o eth1 -p 8443
  router --down
  [ "$status" -eq 0 ]
  recorded "iptables -t nat -D POSTROUTING -o eth1 -m comment --comment hakpak -j MASQUERADE"
  recorded "iptables -t nat -D PREROUTING -i wlan1 -p tcp --dport 8443 -m comment --comment hakpak -j REDIRECT --to-ports 8080"
  recorded "sysctl -w net.ipv4.ip_forward="
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
