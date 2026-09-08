#!/usr/bin/env bash
set -Eeuo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$KIT_DIR/logs"
BACKUP_DIR="$KIT_DIR/backups"
REPORT_DIR="$KIT_DIR/reports"
mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$REPORT_DIR"

_ts(){ date '+%Y-%m-%d %H:%M:%S'; }
info(){ printf '\033[1;34m[%s] INFO\033[0m %s\n' "$(_ts)" "$*"; }
ok(){ printf '\033[1;32m[%s] OK\033[0m %s\n' "$(_ts)" "$*"; }
warn(){ printf '\033[1;33m[%s] WARN\033[0m %s\n' "$(_ts)" "$*"; }
err(){ printf '\033[1;31m[%s] ERROR\033[0m %s\n' "$(_ts)" "$*" >&2; }
die(){ err "$*"; exit 1; }

require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Please run as root: sudo $0"; }

ubuntu_version(){ . /etc/os-release 2>/dev/null || true; printf '%s' "${VERSION_ID:-unknown}"; }
check_ubuntu(){
  . /etc/os-release 2>/dev/null || die "Cannot read /etc/os-release"
  [[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu only. Detected: ${ID:-unknown}"
  case "${VERSION_ID:-}" in 22.04|24.04) ;; *) warn "Tested on Ubuntu 22.04/24.04; detected ${VERSION_ID:-unknown}. Continue with caution.";; esac
}

apt_install_missing(){
  local pkgs=("$@") missing=() p
  for p in "${pkgs[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if ((${#missing[@]})); then
    info "Installing missing packages: ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  fi
}

backup_file(){
  local f="$1"; [[ -e "$f" ]] || return 0
  local dst="$BACKUP_DIR/$(basename "$f").$(date '+%Y%m%d-%H%M%S').bak"
  cp -a "$f" "$dst"; info "Backup: $f -> $dst"
}

public_ipv4(){
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
  [[ -n "$ip" ]] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  printf '%s' "$ip"
}

default_iface(){ ip -4 route show default 2>/dev/null | awk 'NR==1{print $5}'; }

port_owner(){ ss -ltnp 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {print; found=1} END{exit !found}'; }

service_state(){ systemctl is-active "$1" 2>/dev/null || true; }
service_enabled(){ systemctl is-enabled "$1" 2>/dev/null || true; }
