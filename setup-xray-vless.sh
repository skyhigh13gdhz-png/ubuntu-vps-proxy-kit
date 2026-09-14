#!/usr/bin/env bash
set -Eeuo pipefail

# Tencent/China VPS -> Xray client -> VLESS Malaysia node
# Usage:
#   sudo bash setup-xray-vless.sh 'vless://...'
#
# Default routing:
#   private + CN -> DIRECT
#   everything else -> Malaysia VLESS
#
# Local proxy:
#   SOCKS5: 127.0.0.1:10808
#   HTTP:   127.0.0.1:10809

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_INSTALLER="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[+] $*"; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Please run as root (sudo)."
[[ $# -ge 1 ]] || die "Usage: sudo bash $0 'vless://...'"

VLESS_URI="$1"
[[ "$VLESS_URI" == vless://* ]] || die "The first argument must be a vless:// URI."

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates python3 jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates python3 jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates python3 jq
  else
    die "Unsupported distro: apt/dnf/yum not found."
  fi
}

install_xray() {
  if command -v xray >/dev/null 2>&1; then
    info "Xray already installed: $(xray version | head -n1)"
    return
  fi
  info "Installing Xray using the official XTLS installer..."
  tmp="$(mktemp)"
  curl -fL --retry 3 --connect-timeout 15 "$XRAY_INSTALLER" -o "$tmp" \
    || die "Failed to download the official Xray installer from GitHub."
  bash "$tmp" install
  rm -f "$tmp"
}

make_config() {
  mkdir -p "$(dirname "$XRAY_CONFIG")"
  if [[ -f "$XRAY_CONFIG" ]]; then
    cp -a "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
  fi

  VLESS_URI="$VLESS_URI" python3 - "$XRAY_CONFIG" <<'PY'
import json, os, sys
from urllib.parse import urlsplit, parse_qs, unquote

uri = os.environ["VLESS_URI"]
out = sys.argv[1]

u = urlsplit(uri)
if u.scheme.lower() != "vless":
    raise SystemExit("Not a VLESS URI")

uuid = unquote(u.username or "")
host = u.hostname
port = u.port
if not uuid or not host or not port:
    raise SystemExit("VLESS URI is missing UUID, host, or port")

q = {k: v[-1] for k, v in parse_qs(u.query, keep_blank_values=True).items()}

network = (q.get("type") or "tcp").lower()
security = (q.get("security") or "none").lower()
flow = q.get("flow") or ""
encryption = q.get("encryption") or "none"

user = {"id": uuid, "encryption": encryption}
if flow:
    user["flow"] = flow

stream = {
    "network": network,
    "security": security,
}

# TLS
if security == "tls":
    tls = {}
    sni = q.get("sni") or q.get("serverName")
    if sni:
        tls["serverName"] = sni
    fp = q.get("fp")
    if fp:
        tls["fingerprint"] = fp
    alpn = q.get("alpn")
    if alpn:
        tls["alpn"] = [x for x in alpn.split(",") if x]
    if (q.get("allowInsecure") or "").lower() in ("1", "true", "yes"):
        tls["allowInsecure"] = True
    stream["tlsSettings"] = tls

# REALITY
elif security == "reality":
    reality = {}
    sni = q.get("sni") or q.get("serverName")
    if sni:
        reality["serverName"] = sni
    fp = q.get("fp")
    if fp:
        reality["fingerprint"] = fp
    pbk = q.get("pbk") or q.get("publicKey")
    if pbk:
        reality["publicKey"] = pbk
    sid = q.get("sid") or q.get("shortId")
    if sid:
        reality["shortId"] = sid
    spx = q.get("spx") or q.get("spiderX")
    if spx:
        reality["spiderX"] = spx
    stream["realitySettings"] = reality

# Transport
if network == "ws":
    ws = {}
    path = q.get("path")
    if path:
        ws["path"] = path
    host_hdr = q.get("host")
    if host_hdr:
        ws["headers"] = {"Host": host_hdr}
    stream["wsSettings"] = ws

elif network == "grpc":
    grpc = {}
    service = q.get("serviceName") or q.get("path")
    if service:
        grpc["serviceName"] = service
    authority = q.get("authority")
    if authority:
        grpc["authority"] = authority
    if (q.get("mode") or "").lower() == "multi":
        grpc["multiMode"] = True
    stream["grpcSettings"] = grpc

elif network == "xhttp":
    xh = {}
    path = q.get("path")
    if path:
        xh["path"] = path
    host_hdr = q.get("host")
    if host_hdr:
        xh["host"] = host_hdr
    mode = q.get("mode")
    if mode:
        xh["mode"] = mode
    stream["xhttpSettings"] = xh

elif network == "tcp":
    # Plain TCP needs no extra transport settings for normal VLESS/REALITY.
    pass

config = {
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "tag": "socks-local",
            "listen": "127.0.0.1",
            "port": 10808,
            "protocol": "socks",
            "settings": {
                "udp": True
            }
        },
        {
            "tag": "http-local",
            "listen": "127.0.0.1",
            "port": 10809,
            "protocol": "http",
            "settings": {}
        }
    ],
    "outbounds": [
        {
            "tag": "malaysia",
            "protocol": "vless",
            "settings": {
                "vnext": [{
                    "address": host,
                    "port": port,
                    "users": [user]
                }]
            },
            "streamSettings": stream
        },
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        {
            "tag": "block",
            "protocol": "blackhole"
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": ["geoip:private", "geoip:cn"],
                "outboundTag": "direct"
            },
            {
                "type": "field",
                "domain": ["geosite:cn"],
                "outboundTag": "direct"
            }
        ]
    }
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(config, f, ensure_ascii=False, indent=2)

# Only print non-secret summary.
print(f"Parsed VLESS: host={host}, port={port}, network={network}, security={security}")
PY

  chmod 600 "$XRAY_CONFIG"
}

start_and_test() {
  info "Validating Xray configuration..."
  xray run -test -config "$XRAY_CONFIG"

  systemctl daemon-reload
  systemctl enable --now xray
  sleep 2
  systemctl is-active --quiet xray || {
    systemctl status xray --no-pager -l || true
    journalctl -u xray -n 80 --no-pager || true
    die "Xray failed to start."
  }

  info "Xray is running."
  echo
  echo "Local proxies:"
  echo "  SOCKS5  socks5h://127.0.0.1:10808"
  echo "  HTTP    http://127.0.0.1:10809"
  echo
  echo "Routing:"
  echo "  Private/CN -> DIRECT"
  echo "  Everything else -> Malaysia VLESS"
  echo

  info "Testing direct public IP..."
  DIRECT_IP="$(curl -4fsS --max-time 10 https://api.ipify.org || true)"
  echo "  Direct IP: ${DIRECT_IP:-<failed>}"

  info "Testing Malaysia proxy public IP..."
  PROXY_IP="$(curl -4fsS --max-time 20 --socks5-hostname 127.0.0.1:10808 https://api.ipify.org || true)"
  echo "  Proxy IP:  ${PROXY_IP:-<failed>}"

  if [[ -n "$PROXY_IP" && "$PROXY_IP" != "$DIRECT_IP" ]]; then
    echo
    echo "SUCCESS: proxy path is working."
  else
    echo
    echo "WARNING: proxy IP test did not clearly confirm a different egress IP."
    echo "Check: journalctl -u xray -n 100 --no-pager"
  fi
}

install_deps
install_xray
make_config
start_and_test
