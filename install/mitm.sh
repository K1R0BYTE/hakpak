#!/usr/bin/env bash
# MiTM section: rogue access point and traffic interception.
# shellcheck source=install/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# hostapd: Wi-Fi access point
# dnsmasq-base: DHCP + DNS for the access point's clients. The -base package
#   has no system service, so it doesn't fight systemd-resolved for port 53;
#   you start it yourself when you need it.
# iptables: NAT and redirect rules
# tcpdump: packet capture
install_tool apt mitm-packages "hostapd dnsmasq-base iptables tcpdump"
install_tool pipx mitmproxy

install_summary
