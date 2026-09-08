#!/usr/bin/env bash
set -Eeuo pipefail

C_RESET='\033[0m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_BLUE='\033[0;34m'
info(){ echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
ok(){ echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn(){ echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
fail(){ echo -e "${C_RED}[FAIL]${C_RESET} $*"; }
has(){ command -v "$1" >/dev/null 2>&1; }

require_root(){
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "Please run as root: sudo -i"
    exit 1
  fi
}

require_ubuntu(){
  [[ -r /etc/os-release ]] || { fail "/etc/os-release not found"; exit 1; }
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || { fail "V1 supports Ubuntu only (detected: ${ID:-unknown})"; exit 1; }
  ok "Ubuntu ${VERSION_ID:-unknown} detected"
}

apt_install_missing(){
  local missing=() p
  for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if ((${#missing[@]})); then
    info "Installing missing packages: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y "${missing[@]}"
  else
    ok "Required packages already installed"
  fi
}

public_ipv4(){
  local ip=''
  for u in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip=$(curl -4fsS --max-time 5 "$u" 2>/dev/null | tr -d '[:space:]') || true
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$ip"; return 0; }
  done
  return 1
}
