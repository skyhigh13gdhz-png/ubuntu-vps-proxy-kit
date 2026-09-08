#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
cat <<'EOF2'
Reality client helper
=====================
The kit intentionally does not guess your Reality target/SNI or overwrite a working 3X-UI inbound.
Create the VLESS + Reality inbound in 3X-UI, then fill these values:
EOF2
read -r -p "Server IP [$(public_ipv4)]: " SERVER; SERVER=${SERVER:-$(public_ipv4)}
read -r -p "Port [443]: " PORT; PORT=${PORT:-443}
read -r -p "UUID: " UUID
read -r -p "SNI / serverName: " SNI
read -r -p "Reality public key: " PBK
read -r -p "Short ID: " SID
read -r -p "Node name [Ubuntu-Reality]: " NAME; NAME=${NAME:-Ubuntu-Reality}
URI="vless://${UUID}@${SERVER}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp#${NAME}"
echo; echo "$URI"; echo
if command -v qrencode >/dev/null 2>&1; then qrencode -t ANSIUTF8 "$URI"; fi
