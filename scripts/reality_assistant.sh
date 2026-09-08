#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
apt_install_missing uuid-runtime openssl curl

IPV4="$(public_ipv4)"
UUID="$(uuidgen)"
SHORT_ID="$(openssl rand -hex 8)"
XRAY_BIN=''
for candidate in /usr/local/x-ui/bin/xray-linux-* /usr/local/bin/xray /usr/bin/xray; do
  if [[ -x "$candidate" ]]; then XRAY_BIN="$candidate"; break; fi
done

PRIVATE_KEY=''; PUBLIC_KEY=''
if [[ -n "$XRAY_BIN" ]]; then
  out="$($XRAY_BIN x25519 2>/dev/null || true)"
  PRIVATE_KEY="$(awk -F': ' '/Private key|PrivateKey/ {print $2; exit}' <<<"$out")"
  PUBLIC_KEY="$(awk -F': ' '/Public key|PublicKey/ {print $2; exit}' <<<"$out")"
fi

TARGET="${REALITY_TARGET:-}"
if [[ -z "$TARGET" ]]; then
  cat <<'MSG'
Reality target/SNI is the one item v1.0 does not choose blindly.
Choose a stable external HTTPS hostname that supports TLS 1.3 and HTTP/2 and is network-plausible for your VPS.
Avoid copying a target just because it is popular; this project does not default to Apple/iCloud targets.
MSG
  if [[ -t 0 ]]; then read -r -p "Target hostname (example: www.example.com): " TARGET; fi
fi
[[ -n "$TARGET" ]] || die "No target hostname supplied. Re-run with REALITY_TARGET=hostname or enter one interactively."

info "Checking target: $TARGET"
TLS_TMP="$(mktemp)"
trap 'rm -f "$TLS_TMP"' EXIT
if ! timeout 8 openssl s_client -connect "$TARGET:443" -servername "$TARGET" -tls1_3 </dev/null >"$TLS_TMP" 2>&1; then
  die "TLS 1.3 handshake to $TARGET:443 failed. Choose another target."
fi
if curl -fsSI --http2 --max-time 8 "https://$TARGET/" >/dev/null 2>&1; then ok "Target accepts HTTP/2 HTTPS"; else warn "HTTP/2 HEAD check was inconclusive; verify target manually"; fi

SECRET="$REPORT_DIR/reality-secret-$(timestamp).txt"
{
  echo "Server=$IPV4"
  echo "Port=443"
  echo "UUID=$UUID"
  echo "Target=$TARGET:443"
  echo "SNI=$TARGET"
  echo "ShortID=$SHORT_ID"
  [[ -n "$PRIVATE_KEY" ]] && echo "PrivateKey=$PRIVATE_KEY"
  [[ -n "$PUBLIC_KEY" ]] && echo "PublicKey=$PUBLIC_KEY"
} > "$SECRET"
chmod 600 "$SECRET"

cat <<OUT

=== 3X-UI Reality fields ===
Remark:       VPS-Reality-443
Protocol:     VLESS
Listen addr:  blank (all IPs)
Port:         443
Flow:         disabled / empty
Transport:    RAW
Security:     Reality
uTLS:         chrome
Target:       $TARGET:443
SNI:          $TARGET
UUID:         $UUID
Short ID:     $SHORT_ID
OUT
if [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]]; then
  echo "Private Key:  $PRIVATE_KEY"
  echo "Public Key:   $PUBLIC_KEY"
else
  warn "Could not auto-generate X25519 keys from the installed Xray binary. Use 3X-UI's Generate button for the key pair."
fi
cat <<OUT

Sensitive parameter file saved with mode 600:
$SECRET

After creating the inbound in 3X-UI, run Health Check, then create/import the client node.
OUT
