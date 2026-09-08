#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"
require_root
require_ubuntu
apt_install_missing curl iproute2 lsof

info "=== Post-install verification ==="
IP=$(public_ipv4 || true)
[[ -n "$IP" ]] && ok "Public IPv4: $IP" || warn "Public IPv4 lookup failed"

if systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service'; then
  if systemctl is-active --quiet x-ui; then ok "x-ui service: active"; else fail "x-ui service: not active"; fi
else
  fail "x-ui service not installed"
fi

info "Relevant listening TCP sockets:"
ss -lntp | grep -E 'xray|x-ui|:443\b' || ss -lntp || true

if curl -4fsSI --max-time 10 https://www.google.com >/dev/null 2>&1; then ok "VPS HTTPS outbound: PASS"; else warn "VPS HTTPS outbound: FAIL"; fi

echo ""
info "Server-side verification complete."
echo "The remaining decisive test is the real client connection."
echo "Do not treat ping success/failure alone as proof that the proxy node works or fails."
