#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
REPORT="$REPORT_DIR/health-$(timestamp).txt"
exec > >(tee "$REPORT") 2>&1

IPV4="$(public_ipv4)"; IFACE="$(default_iface)"
echo "==== Ubuntu VPS Proxy Kit - Health Check ===="
print_kv "Public IPv4" "${IPV4:-UNKNOWN}"
print_kv "Default interface" "${IFACE:-UNKNOWN}"

failures=0
if service_active x-ui; then ok "x-ui service active"; else warn "x-ui service not active"; failures=$((failures+1)); fi
if ss -ltnp 2>/dev/null | grep -qE '(:|\])443[[:space:]]'; then ok "TCP 443 listening"; else warn "TCP 443 not listening"; failures=$((failures+1)); fi
if service_active unbound; then ok "Unbound active"; else warn "Unbound inactive"; failures=$((failures+1)); fi
if dig @127.0.0.1 example.com +time=3 +tries=1 >/dev/null 2>&1; then ok "Local Unbound query works"; else warn "Local Unbound query failed"; failures=$((failures+1)); fi
if dig example.net +time=3 +tries=1 >/dev/null 2>&1; then ok "System DNS works"; else warn "System DNS failed"; failures=$((failures+1)); fi

if [[ -L /etc/resolv.conf ]]; then
  print_kv "/etc/resolv.conf" "symlink -> $(readlink -f /etc/resolv.conf)"
  if systemctl is-active --quiet systemd-resolved 2>/dev/null && grep -Rqs 'DNS=127.0.0.1' /etc/systemd/resolved.conf.d 2>/dev/null; then ok "systemd-resolved points to Unbound"; fi
else
  ns="$(awk '/^nameserver/{print $2}' /etc/resolv.conf | paste -sd, -)"
  print_kv "System nameserver(s)" "${ns:-NONE}"
  [[ "$ns" == "127.0.0.1" ]] && ok "resolv.conf points to Unbound" || warn "resolv.conf does not exclusively point to 127.0.0.1"
fi

if [[ -n "$IFACE" ]] && command -v ethtool >/dev/null 2>&1; then
  for key in tcp-segmentation-offload generic-segmentation-offload generic-receive-offload; do
    val="$(ethtool -k "$IFACE" 2>/dev/null | awk -F': ' -v k="$key" '$1==k{print $2; exit}')"
    print_kv "$key" "${val:-UNKNOWN}"
  done
fi
print_kv "rp_filter(all)" "$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo UNKNOWN)"

echo
if ((failures==0)); then ok "Overall: PASS"; else warn "Overall: $failures item(s) need attention"; fi
info "Report saved: $REPORT"
