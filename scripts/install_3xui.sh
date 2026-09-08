#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
apt_install_missing curl ca-certificates

if systemctl list-unit-files 2>/dev/null | grep -q '^x-ui.service' || command -v x-ui >/dev/null 2>&1; then
  warn "3X-UI already appears to be installed. Refusing to overwrite automatically."
  systemctl status x-ui --no-pager 2>/dev/null || true
  exit 0
fi

owner443="$(port_owner 443)"
if [[ -n "$owner443" ]]; then
  warn "TCP 443 is already occupied. Reality normally uses 443."
  echo "$owner443"
  die "Resolve the port conflict before installing/configuring the node."
fi

cat <<'MSG'
This step uses the official MHSanaei/3x-ui installer.
It installs the x-ui service and bundled Xray. The official installer may generate panel credentials/path.
MSG
if ! confirm "Install 3X-UI now?" "N"; then exit 0; fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsSL https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TMP"
info "Downloaded official installer. SHA256: $(sha256sum "$TMP" | awk '{print $1}')"

# Prefer official non-interactive mode if supported by current installer; fall back to interactive execution.
if grep -q 'XUI_NONINTERACTIVE' "$TMP"; then
  info "Official installer supports non-interactive mode; using it."
  XUI_NONINTERACTIVE=1 bash "$TMP"
else
  warn "Non-interactive flag not detected in current installer; running official interactive installer."
  bash "$TMP"
fi

systemctl daemon-reload
if service_active x-ui; then ok "x-ui service is active"; else die "x-ui installation finished but service is not active"; fi
if command -v x-ui >/dev/null 2>&1; then ok "x-ui management command available"; fi

# Bind the panel to loopback so it is not exposed publicly. This mirrors an option in the official installer.
XUI_BIN="/usr/local/x-ui/x-ui"
if [[ -x "$XUI_BIN" ]]; then
  if "$XUI_BIN" setting -listenIP "127.0.0.1" >/dev/null 2>&1; then
    systemctl restart x-ui
    ok "3X-UI panel bound to 127.0.0.1 only"
    settings="$($XUI_BIN setting -show 2>/dev/null || true)"
    port="$(awk -F': ' '/^port:/ {print $2; exit}' <<<"$settings")"
    base="$(awk -F': ' '/^webBasePath:/ {print $2; exit}' <<<"$settings")"
    [[ -n "$port" ]] && info "SSH tunnel: ssh -L ${port}:127.0.0.1:${port} root@YOUR_VPS_IP"
    [[ -n "$port" ]] && info "Panel URL after tunneling: http://127.0.0.1:${port}${base:-/}"
  else
    warn "Could not bind panel automatically. Run: /usr/local/x-ui/x-ui setting -listenIP 127.0.0.1"
  fi
fi

if [[ -f /etc/x-ui/install-result.env ]]; then
  info "Official install result: /etc/x-ui/install-result.env (root-readable; may contain credentials)"
  chmod 600 /etc/x-ui/install-result.env || true
fi

warn "v1.0 intentionally does NOT edit the 3X-UI database automatically. Run the Reality Assistant next; it generates safe parameters and exact panel fields without brittle DB writes."
