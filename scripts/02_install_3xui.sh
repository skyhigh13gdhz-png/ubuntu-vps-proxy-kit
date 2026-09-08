#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root; check_ubuntu
apt_install_missing curl ca-certificates

if command -v x-ui >/dev/null 2>&1 || systemctl list-unit-files 2>/dev/null | grep -q '^x-ui.service'; then
  ok "3X-UI appears to be installed already"
  systemctl status x-ui --no-pager || true
  exit 0
fi

cat <<'MSG'
This step uses the official 3X-UI installer from MHSanaei/3x-ui.
The upstream installer is interactive and generates random panel credentials/path.
No existing proxy stack will be silently removed by this wrapper.
MSG
read -r -p "Install 3X-UI now? [Y/n] " ans
[[ "${ans:-Y}" =~ ^[Yy]$ ]] || { warn "Skipped"; exit 0; }

if systemctl list-unit-files 2>/dev/null | grep -Eq '^(xray|s-ui)\.service'; then
  warn "Existing xray/s-ui service detected. Stopping to avoid accidental overwrite."
  systemctl --no-pager status xray s-ui 2>/dev/null || true
  die "Resolve the existing proxy stack manually, then re-run."
fi

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

if systemctl is-active --quiet x-ui; then
  ok "3X-UI installed and running"
  echo
  echo "Run 'x-ui' to view/reset panel credentials and settings."
  echo "Recommended: do NOT expose the panel publicly long-term; prefer SSH tunnel access."
else
  die "3X-UI installation finished but x-ui is not active"
fi
