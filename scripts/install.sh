#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$DIR/common.sh"

require_root
require_ubuntu
apt_install_missing curl wget ca-certificates openssl socat jq unzip tar iproute2 lsof

info "Checking existing installation..."
if systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service'; then
  warn "x-ui service already exists. Installer will not overwrite it automatically."
  systemctl --no-pager --full status x-ui 2>/dev/null | sed -n '1,12p' || true
  exit 0
fi

cat <<'EOF'

This installer uses the upstream 3x-ui installer.
It installs the panel/Xray stack; it does NOT silently create a public proxy inbound.
After installation, create and review the VLESS + Reality inbound in the panel.

EOF

read -r -p "Continue installing 3x-ui? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { info "Cancelled"; exit 0; }

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -fsSL --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TMP"
info "Downloaded upstream installer. Starting installation..."
bash "$TMP"

if systemctl is-active --quiet x-ui 2>/dev/null; then
  ok "x-ui service is running"
else
  warn "x-ui is not active. Run scripts/collect-report.sh before changing random settings."
fi

IP=$(public_ipv4 || true)
[[ -n "$IP" ]] && info "VPS IPv4: $IP"
echo ""
info "Next: configure a VLESS + Reality inbound in 3x-ui, then run scripts/verify.sh"
