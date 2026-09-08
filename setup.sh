#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/lib/common.sh"
require_root
check_ubuntu

run(){ bash "$ROOT/scripts/$1"; }
while true; do
  cat <<'MENU'

Ubuntu VPS Proxy Kit
====================
1. New VPS Setup (guided)
2. Bootstrap dependencies
3. Pre-check VPS
4. Install / verify 3X-UI + Xray
5. Setup / repair Unbound DNS
6. Health check
7. Advanced diagnostics
0. Exit
MENU
  read -r -p "Select: " n
  case "$n" in
    1) run 00_bootstrap.sh; run 01_precheck.sh; run 02_install_3xui.sh; run 03_setup_unbound.sh; run 05_health_check.sh ;;
    2) run 00_bootstrap.sh ;;
    3) run 01_precheck.sh ;;
    4) run 02_install_3xui.sh ;;
    5) run 03_setup_unbound.sh ;;
    6) run 05_health_check.sh ;;
    7) run 06_diagnostics.sh ;;
    0) exit 0 ;;
    *) warn "Invalid selection" ;;
  esac
done
