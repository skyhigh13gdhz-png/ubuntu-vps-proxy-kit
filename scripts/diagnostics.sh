#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
apt_install_missing ethtool traceroute tcpdump dnsutils
REPORT="$REPORT_DIR/diagnostics-$(timestamp).txt"
exec > >(tee "$REPORT") 2>&1
IFACE="$(default_iface)"
echo "==== Advanced Diagnostics (read-only) ===="
echo "-- ip addr --"; ip addr
echo "-- ip route --"; ip route show table all
echo "-- ip rule --"; ip rule show
echo "-- nftables --"; nft list ruleset 2>/dev/null || true
echo "-- iptables filter --"; iptables -S 2>/dev/null || true
echo "-- iptables nat --"; iptables -t nat -S 2>/dev/null || true
echo "-- iptables mangle --"; iptables -t mangle -S 2>/dev/null || true
echo "-- iptables raw --"; iptables -t raw -S 2>/dev/null || true
echo "-- rp_filter --"; sysctl net.ipv4.conf.all.rp_filter 2>/dev/null || true; [[ -n "$IFACE" ]] && sysctl "net.ipv4.conf.${IFACE}.rp_filter" 2>/dev/null || true
echo "-- link --"; [[ -n "$IFACE" ]] && ip link show "$IFACE" || true
echo "-- offload --"; [[ -n "$IFACE" ]] && ethtool -k "$IFACE" 2>/dev/null || true
echo "-- listeners --"; ss -lntup
echo "-- resolv.conf --"; ls -l /etc/resolv.conf; cat /etc/resolv.conf 2>/dev/null || true
echo "-- unbound forwarders --"; grep -RniE 'forward-zone|forward-addr|stub-zone' /etc/unbound 2>/dev/null || true
info "Diagnostic report saved: $REPORT"
warn "This script does not change MTU, rp_filter, routing, firewall, or offload settings."
