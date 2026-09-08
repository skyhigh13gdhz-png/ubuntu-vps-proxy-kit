#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root; check_ubuntu
REPORT="$REPORT_DIR/precheck-$(date '+%Y%m%d-%H%M%S').txt"
{
  echo "Ubuntu VPS Proxy Kit - Precheck"
  echo "Time: $(date -Is)"
  echo "Ubuntu: $(ubuntu_version)"
  echo "Kernel: $(uname -r)"
  echo "IPv4: $(public_ipv4)"
  echo "Default iface: $(default_iface)"
  echo
  echo "== Route =="; ip -4 route
  echo
  echo "== DNS =="; cat /etc/resolv.conf 2>/dev/null || true
  echo
  echo "== Time sync =="; timedatectl show -p NTPSynchronized -p TimeUSec 2>/dev/null || true
  echo
  echo "== Ports =="; ss -ltnp | grep -E ':(22|53|80|443|2053)\b' || true
  echo
  echo "== Firewall =="; nft list ruleset 2>/dev/null || iptables -S 2>/dev/null || true
  echo
  echo "== rp_filter =="; sysctl net.ipv4.conf.all.rp_filter 2>/dev/null || true; [[ -n "$(default_iface)" ]] && sysctl "net.ipv4.conf.$(default_iface).rp_filter" 2>/dev/null || true
  echo
  echo "== Offload =="; [[ -n "$(default_iface)" ]] && ethtool -k "$(default_iface)" 2>/dev/null | grep -E 'tcp-segmentation-offload:|generic-segmentation-offload:|generic-receive-offload:' || true
  echo
  echo "== Services =="; for s in x-ui xray unbound; do printf '%-12s active=%s enabled=%s\n' "$s" "$(service_state "$s")" "$(service_enabled "$s")"; done
} | tee "$REPORT"

if port_owner 443 >/dev/null 2>&1; then warn "TCP 443 is already occupied. Review before creating a Reality inbound."; else ok "TCP 443 is free"; fi
ok "Precheck report saved: $REPORT"
