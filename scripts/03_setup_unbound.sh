#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root; check_ubuntu
apt_install_missing unbound dnsutils

CONF=/etc/unbound/unbound.conf.d/vps-proxy-kit.conf
backup_file "$CONF"; backup_file /etc/resolv.conf
cat > "$CONF" <<'CONFEOF'
server:
  interface: 127.0.0.1
  interface: ::1
  port: 53
  access-control: 127.0.0.0/8 allow
  access-control: ::1 allow
  hide-identity: yes
  hide-version: yes
  qname-minimisation: yes
  prefetch: yes
  harden-glue: yes
  harden-dnssec-stripped: yes
  use-caps-for-id: no
CONFEOF

unbound-checkconf
systemctl enable --now unbound
if ! dig +time=5 +tries=1 @127.0.0.1 example.com A >/dev/null 2>&1; then
  die "Unbound local recursion test failed; /etc/resolv.conf was not changed"
fi

printf 'nameserver 127.0.0.1\n' > /etc/resolv.conf
if dig +time=5 +tries=1 example.com A >/dev/null 2>&1; then
  ok "System DNS now uses local Unbound (127.0.0.1)"
else
  latest=$(ls -1t "$BACKUP_DIR"/resolv.conf.*.bak 2>/dev/null | head -1 || true)
  [[ -n "$latest" ]] && cp -a "$latest" /etc/resolv.conf
  die "DNS verification failed; restored previous resolv.conf"
fi

if grep -RniE 'forward-zone|forward-addr|stub-zone' /etc/unbound 2>/dev/null | grep -v 'vps-proxy-kit.conf' >/dev/null; then
  warn "Existing Unbound forward/stub configuration detected elsewhere. Review manually if you require full recursion."
else
  ok "No explicit forwarder detected; Unbound is configured for recursive resolution"
fi
