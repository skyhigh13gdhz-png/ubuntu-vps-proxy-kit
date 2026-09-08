#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$DIR/common.sh"

require_root
require_ubuntu
apt_install_missing curl ca-certificates iproute2 iputils-ping dnsutils net-tools lsof jq openssl

echo ""
info "=== Ubuntu VPS pre-install diagnostics ==="

printf '%-24s %s\n' "Hostname:" "$(hostname)"
printf '%-24s %s\n' "Kernel:" "$(uname -r)"
printf '%-24s %s\n' "Architecture:" "$(uname -m)"
printf '%-24s %s\n' "Memory:" "$(free -h | awk '/Mem:/ {print $2}')"
printf '%-24s %s\n' "Disk /:" "$(df -h / | awk 'NR==2 {print $2" total, "$4" free"}')"

IP=$(public_ipv4 || true)
[[ -n "$IP" ]] && ok "Public IPv4: $IP" || warn "Unable to determine public IPv4"

if getent ahostsv4 google.com >/dev/null 2>&1; then ok "DNS resolution works"; else fail "DNS resolution failed"; fi
if curl -4fsSI --max-time 10 https://www.google.com >/dev/null 2>&1; then ok "HTTPS outbound connectivity works"; else warn "Google HTTPS outbound test failed"; fi
if curl -4fsSI --max-time 10 https://github.com >/dev/null 2>&1; then ok "GitHub HTTPS reachable"; else warn "GitHub HTTPS test failed"; fi

if has ufw; then
  info "UFW status:"
  ufw status || true
else
  info "UFW not installed"
fi

info "Listening TCP ports:"
ss -lntp || true

if has xray; then ok "Xray binary found: $(command -v xray)"; else info "Xray binary not found"; fi
if systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service'; then
  ok "x-ui systemd service exists"
  systemctl --no-pager --full status x-ui 2>/dev/null | sed -n '1,12p' || true
else
  info "3x-ui/x-ui systemd service not found"
fi

echo ""
info "Interpretation"
echo "- This report checks the VPS itself."
echo "- Successful VPS outbound access does NOT prove a mainland-China client can reach this VPS."
echo "- If the server looks healthy, continue with scripts/install.sh."
