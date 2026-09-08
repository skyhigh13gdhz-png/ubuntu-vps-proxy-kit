#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu

REPORT="$REPORT_DIR/precheck-$(timestamp).txt"
exec > >(tee "$REPORT") 2>&1

IPV4="$(public_ipv4)"; IFACE="$(default_iface)"
load_os

echo "==== Ubuntu VPS Proxy Kit - Precheck ===="
print_kv "Time (UTC)" "$(date -u --iso-8601=seconds)"
print_kv "Ubuntu" "$OS_VERSION_ID"
print_kv "Kernel" "$(uname -r)"
print_kv "Public IPv4" "${IPV4:-UNKNOWN}"
print_kv "Default interface" "${IFACE:-UNKNOWN}"
print_kv "Default route" "$(ip route show default | head -1)"
print_kv "IPv6" "$(ip -6 addr show scope global 2>/dev/null | grep -q 'inet6' && echo AVAILABLE || echo NONE)"
print_kv "NTP synchronized" "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo UNKNOWN)"
print_kv "Disk /" "$(df -h / | awk 'NR==2{print $4" free / "$2}')"
print_kv "Memory" "$(free -h | awk '/Mem:/ {print $7" available / "$2}')"

echo
for p in 53 80 443 2053; do
  owner="$(port_owner "$p")"
  if [[ -n "$owner" ]]; then warn "TCP port $p is in use: $owner"; else ok "TCP port $p is free"; fi
done

echo
if command -v x-ui >/dev/null 2>&1 || systemctl list-unit-files 2>/dev/null | grep -q '^x-ui.service'; then
  ok "3X-UI detected"
  print_kv "x-ui service" "$(systemctl is-active x-ui 2>/dev/null || true)"
else
  warn "3X-UI not installed"
fi
if pgrep -af 'xray' >/dev/null 2>&1; then ok "Xray process detected"; else warn "Xray process not detected"; fi
if service_active unbound; then ok "Unbound running"; else warn "Unbound not running"; fi

if command -v ufw >/dev/null 2>&1; then print_kv "UFW" "$(ufw status 2>/dev/null | head -1)"; fi
print_kv "rp_filter all" "$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo UNKNOWN)"
if [[ -n "$IFACE" ]]; then
  print_kv "$IFACE MTU" "$(ip link show "$IFACE" | awk '/mtu/{for(i=1;i<=NF;i++)if($i=="mtu")print $(i+1)}')"
fi

echo
info "Outbound reachability tests"
for host in 1.1.1.1 8.8.8.8; do
  if timeout 5 bash -c "</dev/tcp/$host/443" 2>/dev/null; then ok "$host:443 reachable"; else warn "$host:443 not reachable"; fi
done

# Representative public DNS / network IPs are only directional indicators, not proof of Mainland -> VPS reachability.
for host in 223.5.5.5 119.29.29.29; do
  if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then ok "Outbound ICMP to $host works"; else warn "No ICMP reply from $host (not necessarily a problem)"; fi
done

echo
warn "This precheck cannot prove Mainland China -> VPS inbound reachability. If the finished node cannot connect, run Advanced Diagnostics."
info "Report saved: $REPORT"
