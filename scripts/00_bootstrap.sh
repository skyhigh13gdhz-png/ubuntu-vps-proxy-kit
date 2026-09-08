#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root; check_ubuntu
apt_install_missing curl wget git jq dnsutils traceroute tcpdump netcat-openbsd ethtool lsof unzip ca-certificates openssl qrencode
systemctl is-active systemd-timesyncd >/dev/null 2>&1 || systemctl restart systemd-timesyncd || true
ok "Bootstrap complete"
