#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
require_root
require_ubuntu
apt_install_missing curl iproute2

OUT="${1:-vps-report-$(date +%Y%m%d-%H%M%S).txt}"
{
  echo "Ubuntu VPS Proxy Kit - Diagnostic Report"
  echo "Generated: $(date -Is)"
  echo
  echo "== OS =="
  grep -E '^(NAME|VERSION|ID|VERSION_ID)=' /etc/os-release || true
  uname -a
  echo
  echo "== Resources =="
  free -h || true
  df -h / || true
  echo
  echo "== Network =="
  ip -brief addr || true
  ip route || true
  echo
  echo "== Listening sockets =="
  ss -lntup || true
  echo
  echo "== Firewall =="
  if has ufw; then ufw status verbose || true; else echo "ufw: not installed"; fi
  echo
  echo "== x-ui =="
  systemctl --no-pager --full status x-ui 2>&1 || true
  echo
  echo "== x-ui recent log =="
  journalctl -u x-ui --no-pager -n 100 2>&1 || true
  echo
  echo "== Outbound =="
  curl -4sSIL --max-time 10 -o /dev/null -w 'google http=%{http_code} total=%{time_total}\n' https://www.google.com 2>&1 || true
  curl -4sSIL --max-time 10 -o /dev/null -w 'github http=%{http_code} total=%{time_total}\n' https://github.com 2>&1 || true
} > "$OUT"

# Basic redaction of common public IPv4 appearances. Keep topology useful without publishing the address.
IP=$(public_ipv4 || true)
if [[ -n "$IP" ]]; then sed -i "s/${IP//./\\.}/<PUBLIC_IPV4>/g" "$OUT"; fi

ok "Report written to: $OUT"
warn "Review the report before sharing. Do NOT publish UUIDs, private keys, passwords, tokens or full proxy share links."
