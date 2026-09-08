#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root; check_ubuntu
IP=$(public_ipv4); IFACE=$(default_iface); FAIL=0
pass(){ printf 'PASS  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*"; FAIL=1; }
warnc(){ printf 'WARN  %s\n' "$*"; }

echo "Ubuntu VPS Proxy Kit - Health Check"
echo "IPv4: $IP"; echo
[[ -n "$IP" ]] && pass "Public IPv4 detected" || fail "No public IPv4 detected"
[[ -n "$IFACE" ]] && pass "Default route via $IFACE" || fail "No default IPv4 route"
systemctl is-active --quiet x-ui && pass "3X-UI service active" || warnc "3X-UI service not active/installed"
ss -ltnp | grep -q ':443 ' && pass "TCP 443 is listening" || warnc "TCP 443 is not listening"
systemctl is-active --quiet unbound && pass "Unbound active" || fail "Unbound not active"
grep -Eq '^nameserver[[:space:]]+127\.0\.0\.1$' /etc/resolv.conf 2>/dev/null && pass "resolv.conf -> 127.0.0.1" || warnc "resolv.conf is not pinned to local Unbound"
dig +time=5 +tries=1 @127.0.0.1 example.com A >/dev/null 2>&1 && pass "Local DNS recursion works" || fail "Local DNS recursion failed"
pgrep -x nc >/dev/null 2>&1 && warnc "netcat process is still running" || pass "No leftover netcat listener detected"
pgrep -x tcpdump >/dev/null 2>&1 && warnc "tcpdump is still running" || pass "No leftover tcpdump detected"
if [[ -n "$IFACE" ]]; then
  vals=$(ethtool -k "$IFACE" 2>/dev/null | awk '/tcp-segmentation-offload:|generic-segmentation-offload:|generic-receive-offload:/{print $2}' | tr '\n' ' ')
  [[ "$vals" == *off* ]] && warnc "One or more TSO/GSO/GRO offload features are disabled: $vals" || pass "TSO/GSO/GRO appear enabled"
fi

echo
(( FAIL == 0 )) && ok "Health check completed without hard failures" || die "Health check found failures"
