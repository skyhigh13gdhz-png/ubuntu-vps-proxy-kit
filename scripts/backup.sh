#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
OUT="$BACKUP_DIR/vps-proxy-kit-backup-$(timestamp).tar.gz"
items=()
for p in /etc/x-ui /etc/unbound /etc/systemd/resolved.conf.d/vps-proxy-kit.conf /etc/resolv.conf; do
  [[ -e "$p" || -L "$p" ]] && items+=("$p")
done
((${#items[@]})) || die "No managed configuration found to back up"
tar -czf "$OUT" --absolute-names "${items[@]}"
chmod 600 "$OUT"
ok "Backup created: $OUT"
warn "This archive may contain panel credentials/private keys. Keep it private."
