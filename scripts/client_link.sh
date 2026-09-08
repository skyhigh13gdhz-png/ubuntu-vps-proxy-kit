#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
apt_install_missing qrencode

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
  FILE="$(ls -1t "$REPORT_DIR"/reality-secret-*.txt 2>/dev/null | head -1 || true)"
fi
[[ -n "$FILE" && -f "$FILE" ]] || die "Reality parameter file not found. Pass its path or run Reality Assistant first."
chmod 600 "$FILE" || true

# shellcheck disable=SC1090
source "$FILE"
: "${Server:?}" "${Port:?}" "${UUID:?}" "${SNI:?}" "${ShortID:?}"
if [[ -z "${PublicKey:-}" ]]; then die "PublicKey is missing. Generate keys in 3X-UI and add PublicKey=... to $FILE"; fi
NAME="${NODE_NAME:-VPS-Reality-443}"
URI="vless://${UUID}@${Server}:${Port}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PublicKey}&sid=${ShortID}&type=tcp#${NAME}"

echo "=== Shadowrocket / VLESS URI ==="
echo "$URI"
echo
echo "=== QR Code ==="
qrencode -t ANSIUTF8 "$URI"
