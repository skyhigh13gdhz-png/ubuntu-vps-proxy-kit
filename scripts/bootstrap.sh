#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
apt_install_missing curl wget ca-certificates git jq dnsutils traceroute tcpdump netcat-openbsd ethtool lsof unzip qrencode uuid-runtime openssl
ok "Bootstrap complete"
