#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root; check_ubuntu
apt_install_missing tcpdump netcat-openbsd traceroute ethtool dnsutils
IP=$(public_ipv4); IFACE=$(default_iface)
cat <<EOF2
Advanced Diagnostics
====================
Use this only when the installed node cannot connect from Mainland China.
VPS IPv4: $IP
Interface: $IFACE

1. Snapshot network state
2. Temporary mainland TCP test
3. DNS diagnostics
0. Back
EOF2
read -r -p "Select: " n
case "$n" in
1)
  echo '== ip rule =='; ip rule show
  echo '== routes =='; ip route show table all
  echo '== nft =='; nft list ruleset 2>/dev/null || true
  echo '== iptables =='; iptables -S 2>/dev/null || true
  echo '== rp_filter =='; sysctl net.ipv4.conf.all.rp_filter; [[ -n "$IFACE" ]] && sysctl "net.ipv4.conf.$IFACE.rp_filter" || true
  echo '== offload =='; [[ -n "$IFACE" ]] && ethtool -k "$IFACE" | grep -E 'tcp-segmentation-offload:|generic-segmentation-offload:|generic-receive-offload:' || true
  ;;
2)
  PORT=18080
  if ss -ltn | awk '{print $4}' | grep -qE ":${PORT}$"; then die "Port $PORT already in use"; fi
  LOG="$LOG_DIR/mainland-tcp-$(date '+%Y%m%d-%H%M%S').log"
  echo "Open this URL from a Mainland China network with VPN/proxy OFF: http://$IP:$PORT"
  echo "Waiting up to 90 seconds..."
  timeout 90 tcpdump -ni "$IFACE" "tcp port $PORT" >"$LOG" 2>&1 & TCPDUMP_PID=$!
  timeout 90 nc -lv "$PORT" || true
  kill "$TCPDUMP_PID" 2>/dev/null || true; wait "$TCPDUMP_PID" 2>/dev/null || true
  echo "Packet log: $LOG"
  if grep -q 'GET / HTTP' "$LOG" 2>/dev/null; then ok "HTTP request observed"; else warn "No HTTP payload seen. Inspect the packet log for SYN/SYN-ACK patterns."; fi
  ;;
3)
  cat /etc/resolv.conf || true
  systemctl status unbound --no-pager || true
  dig @127.0.0.1 example.com A || true
  grep -RniE 'forward-zone|forward-addr|stub-zone' /etc/unbound 2>/dev/null || true
  ;;
*) exit 0;;
esac
