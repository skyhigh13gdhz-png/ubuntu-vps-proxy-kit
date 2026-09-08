#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
apt_install_missing unbound dnsutils

CONF=/etc/unbound/unbound.conf.d/vps-proxy-kit.conf
if [[ -f "$CONF" ]]; then backup_file "$CONF" unbound-vps-proxy-kit >/dev/null; fi
HAS_IPV6=no
ip -6 addr show scope global 2>/dev/null | grep -q 'inet6' && HAS_IPV6=yes
cat > "$CONF" <<UCONF
server:
  interface: 127.0.0.1
  interface: ::1
  access-control: 127.0.0.0/8 allow
  access-control: ::1 allow
  do-ip4: yes
  do-ip6: $HAS_IPV6
  do-udp: yes
  do-tcp: yes
  hide-identity: yes
  hide-version: yes
  qname-minimisation: yes
  prefetch: yes
  harden-glue: yes
  harden-dnssec-stripped: yes
UCONF

unbound-checkconf >/dev/null
systemctl enable --now unbound
systemctl restart unbound
sleep 1
service_active unbound || die "Unbound failed to start"

dig @127.0.0.1 example.com +time=4 +tries=1 >/dev/null || die "Unbound test query failed; system DNS has NOT been changed"
ok "Unbound local recursion works"

RESOLV=/etc/resolv.conf
if [[ -L "$RESOLV" ]] && systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved.service'; then
  info "/etc/resolv.conf is managed by systemd-resolved; preserving the symlink and pointing resolved to local Unbound."
  mkdir -p /etc/systemd/resolved.conf.d
  DROPIN=/etc/systemd/resolved.conf.d/vps-proxy-kit.conf
  [[ -f "$DROPIN" ]] && backup_file "$DROPIN" systemd-resolved-vps-proxy-kit >/dev/null
  cat > "$DROPIN" <<'RCONF'
[Resolve]
DNS=127.0.0.1
FallbackDNS=
Domains=~.
RCONF
  systemctl restart systemd-resolved
else
  info "/etc/resolv.conf is a regular/provider-managed file; backing up and switching it to local Unbound."
  backup_file "$RESOLV" resolv.conf >/dev/null
  printf 'nameserver 127.0.0.1\n' > "$RESOLV"
fi

if ! dig example.net +time=4 +tries=1 >/dev/null; then
  fail "System DNS verification failed."
  die "Use backups/ to restore the previous resolver configuration."
fi
ok "System DNS resolves successfully through the local chain"

if grep -RqsE '^[[:space:]]*(forward-zone|forward-addr|stub-zone):' /etc/unbound; then
  warn "Forward/stub configuration exists somewhere under /etc/unbound; review it if you require full recursion."
else
  ok "No Unbound forward-zone/forward-addr/stub-zone found"
fi
