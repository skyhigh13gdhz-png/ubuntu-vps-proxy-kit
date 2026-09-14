#!/usr/bin/env bash
set -Eeuo pipefail

# China VPS -> local Xray client -> overseas VLESS node
# Usage:
#   sudo bash setup-xray-vless.sh
# Then paste the VLESS URI when prompted; input is hidden and is not stored in shell history.
#
# Xray routing:
#   private + CN -> DIRECT
#   everything else -> VLESS
#
# Local proxy:
#   SOCKS5: 127.0.0.1:10808
#   HTTP:   127.0.0.1:10809

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_TMP_DIR="/tmp/xray-bootstrap"

# Mainland-first binary mirror. Each Xray version is stored as a branch in Gitee.
# Override at runtime if needed:
#   XRAY_VERSION=v26.3.27 sudo -E bash setup-xray-vless.sh
XRAY_VERSION="${XRAY_VERSION:-v26.3.27}"
XRAY_GITEE_REPO="https://gitee.com/skyhigh13/xray_bin.git"

# Fallbacks are kept only for resilience when Gitee is unavailable.
XRAY_GITHUB_DOWNLOAD_BASE="https://github.com/XTLS/Xray-core/releases/download"
XRAY_SOURCEFORGE_BASE="https://sourceforge.net/projects/xray-core.mirror/files"
XRAY_MIRRORS=(
  "https://gh.ddlc.top/"
  "https://ghproxy.net/"
)

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[+] $*"; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Please run as root (sudo)."

if [[ $# -ge 1 ]]; then
  VLESS_URI="$1"
else
  read -r -s -p "Paste VLESS URI: " VLESS_URI
  echo
fi
[[ "$VLESS_URI" == vless://* ]] || die "The VLESS URI must start with vless://"

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates python3 jq unzip git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates python3 jq unzip git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates python3 jq unzip git
  else
    die "Unsupported distro: apt/dnf/yum not found."
  fi
}

get_arch_asset() {
  case "$(uname -m)" in
    x86_64|amd64) echo "Xray-linux-64.zip" ;;
    aarch64|arm64) echo "Xray-linux-arm64-v8a.zip" ;;
    armv7l|armv7) echo "Xray-linux-arm32-v7a.zip" ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

download_xray_from_gitee() {
  local version="$1" asset="$2" output="$3"
  local clone_dir="${XRAY_TMP_DIR}/gitee-xray-bin"

  info "Trying mainland Gitee binary mirror (${version})..."
  rm -rf "$clone_dir"

  if ! git -c advice.detachedHead=false clone \
      --quiet \
      --depth 1 \
      --single-branch \
      --branch "$version" \
      "$XRAY_GITEE_REPO" \
      "$clone_dir"; then
    rm -rf "$clone_dir"
    return 1
  fi

  if [[ ! -f "${clone_dir}/${asset}" ]]; then
    info "Gitee branch exists but ${asset} is missing."
    rm -rf "$clone_dir"
    return 1
  fi

  cp -f "${clone_dir}/${asset}" "$output"

  # Prefer the mirrored digest when available. Xray .dgst files contain the
  # official SHA2-256 value. ZIP integrity is still checked afterwards.
  if [[ -f "${clone_dir}/${asset}.dgst" ]]; then
    local expected actual
    expected="$(awk -F '= ' '/256=/{print $2; exit}' "${clone_dir}/${asset}.dgst" | tr -d '[:space:]')"
    actual="$(sha256sum "$output" | awk '{print $1}')"
    if [[ -n "$expected" && "$expected" != "$actual" ]]; then
      info "Gitee SHA256 verification failed."
      rm -rf "$clone_dir" "$output"
      return 1
    fi
    [[ -n "$expected" ]] && info "SHA256 verification passed."
  fi

  rm -rf "$clone_dir"

  unzip -tq "$output" >/dev/null || {
    info "Gitee archive failed ZIP integrity check."
    rm -f "$output"
    return 1
  }

  info "Downloaded ${asset} from Gitee successfully."
  return 0
}

download_xray_fallback() {
  local version="$1" asset="$2" output="$3" mirror
  local github_url="${XRAY_GITHUB_DOWNLOAD_BASE}/${version}/${asset}"
  local sourceforge_url="${XRAY_SOURCEFORGE_BASE}/${version}/${asset}/download"

  info "Gitee unavailable; trying SourceForge fallback..."
  if curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 \
      "$sourceforge_url" -o "$output"; then
    unzip -tq "$output" >/dev/null && return 0
  fi
  rm -f "$output"

  for mirror in "${XRAY_MIRRORS[@]}"; do
    info "Trying GitHub fallback mirror: $mirror"
    if curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 \
        "${mirror}${github_url}" -o "$output"; then
      unzip -tq "$output" >/dev/null && return 0
    fi
    rm -f "$output"
  done

  info "Trying official GitHub as final fallback..."
  if curl -fL --retry 1 --connect-timeout 8 --speed-time 20 --speed-limit 10240 \
      "$github_url" -o "$output"; then
    unzip -tq "$output" >/dev/null && return 0
  fi

  rm -f "$output"
  return 1
}

install_xray() {
  if [[ -x "$XRAY_BIN" ]]; then
    info "Xray already installed: $($XRAY_BIN version | head -n1)"
    return
  fi

  local asset version zip_file
  asset="$(get_arch_asset)"
  version="$XRAY_VERSION"

  rm -rf "$XRAY_TMP_DIR"
  mkdir -p "$XRAY_TMP_DIR"
  zip_file="${XRAY_TMP_DIR}/${asset}"

  info "Installing Xray ${version} (${asset})..."

  if ! download_xray_from_gitee "$version" "$asset" "$zip_file"; then
    download_xray_fallback "$version" "$asset" "$zip_file" \
      || die "Failed to download Xray from Gitee and all fallback sources."
  fi

  unzip -tq "$zip_file" >/dev/null || die "Downloaded Xray archive is corrupt."
  unzip -oq "$zip_file" -d "$XRAY_TMP_DIR"
  [[ -f "${XRAY_TMP_DIR}/xray" ]] || die "Xray binary missing from archive."

  install -m 0755 "${XRAY_TMP_DIR}/xray" "$XRAY_BIN"
  mkdir -p "$XRAY_ASSET_DIR"
  [[ -f "${XRAY_TMP_DIR}/geoip.dat" ]] && install -m 0644 "${XRAY_TMP_DIR}/geoip.dat" "$XRAY_ASSET_DIR/geoip.dat"
  [[ -f "${XRAY_TMP_DIR}/geosite.dat" ]] && install -m 0644 "${XRAY_TMP_DIR}/geosite.dat" "$XRAY_ASSET_DIR/geosite.dat"

  cat >/etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  rm -rf "$XRAY_TMP_DIR"
  info "Xray installed successfully: $($XRAY_BIN version | head -n1)"
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

stream = {"network": network, "security": security}

if security == "tls":
    tls = {}
    sni = q.get("sni") or q.get("serverName")
    if sni: tls["serverName"] = sni
    fp = q.get("fp")
    if fp: tls["fingerprint"] = fp
    alpn = q.get("alpn")
    if alpn: tls["alpn"] = [x for x in alpn.split(",") if x]
    if (q.get("allowInsecure") or "").lower() in ("1", "true", "yes"):
        tls["allowInsecure"] = True
    stream["tlsSettings"] = tls
elif security == "reality":
    reality = {}
    sni = q.get("sni") or q.get("serverName")
    if sni: reality["serverName"] = sni
    fp = q.get("fp")
    if fp: reality["fingerprint"] = fp
    pbk = q.get("pbk") or q.get("publicKey")
    if pbk: reality["publicKey"] = pbk
    sid = q.get("sid") or q.get("shortId")
    if sid: reality["shortId"] = sid
    spx = q.get("spx") or q.get("spiderX")
    if spx: reality["spiderX"] = spx
    stream["realitySettings"] = reality

if network == "ws":
    ws = {}
    path = q.get("path")
    if path: ws["path"] = path
    host_hdr = q.get("host")
    if host_hdr: ws["headers"] = {"Host": host_hdr}
    stream["wsSettings"] = ws
elif network == "grpc":
    grpc = {}
    service = q.get("serviceName") or q.get("path")
    if service: grpc["serviceName"] = service
    authority = q.get("authority")
    if authority: grpc["authority"] = authority
    if (q.get("mode") or "").lower() == "multi": grpc["multiMode"] = True
    stream["grpcSettings"] = grpc
elif network == "xhttp":
    xh = {}
    path = q.get("path")
    if path: xh["path"] = path
    host_hdr = q.get("host")
    if host_hdr: xh["host"] = host_hdr
    mode = q.get("mode")
    if mode: xh["mode"] = mode
    stream["xhttpSettings"] = xh

config = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {"tag": "socks-local", "listen": "127.0.0.1", "port": 10808,
         "protocol": "socks", "settings": {"udp": True}},
        {"tag": "http-local", "listen": "127.0.0.1", "port": 10809,
         "protocol": "http", "settings": {}}
    ],
    "outbounds": [
        {"tag": "malaysia", "protocol": "vless",
         "settings": {"vnext": [{"address": host, "port": port, "users": [user]}]},
         "streamSettings": stream},
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block", "protocol": "blackhole"}
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "ip": ["geoip:private", "geoip:cn"], "outboundTag": "direct"},
            {"type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"}
        ]
    }
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(config, f, ensure_ascii=False, indent=2)

print(f"Parsed VLESS: host={host}, port={port}, network={network}, security={security}")
PY

  chmod 600 "$XRAY_CONFIG"
}

install_proxy_helpers() {
  # Do NOT force a machine-wide proxy. These helpers make proxy use explicit
  # for interactive shell sessions while Xray itself still performs CN/direct
  # versus overseas/VLESS routing.
  cat >/etc/profile.d/xray-proxy.sh <<'EOF'
# Xray local proxy helpers. Run `proxy_on` or `proxy_off` in an interactive shell.
proxy_on() {
  export http_proxy="http://127.0.0.1:10809"
  export https_proxy="http://127.0.0.1:10809"
  export HTTP_PROXY="$http_proxy"
  export HTTPS_PROXY="$https_proxy"
  export ALL_PROXY="socks5h://127.0.0.1:10808"
  export all_proxy="$ALL_PROXY"
  export NO_PROXY="localhost,127.0.0.1,::1"
  export no_proxy="$NO_PROXY"
  echo "Xray proxy enabled for this shell."
}
proxy_off() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy
  echo "Proxy variables cleared for this shell."
}
EOF
  chmod 0644 /etc/profile.d/xray-proxy.sh

  cat >/usr/local/bin/xray-proxy-test <<'EOF'
#!/usr/bin/env bash
set -u
SOCKS="127.0.0.1:10808"
HTTP="http://127.0.0.1:10809"
printf 'Xray service: '
systemctl is-active xray 2>/dev/null || true
printf 'Google via SOCKS: '
curl -o /dev/null -sS -w '%{http_code}\n' --max-time 20 --socks5-hostname "$SOCKS" https://www.google.com/ || true
printf 'GitHub via HTTP:  '
curl -o /dev/null -sS -w '%{http_code}\n' --max-time 20 -x "$HTTP" https://github.com/ || true
printf 'Proxy exit IP:    '
curl -fsS --max-time 20 --socks5-hostname "$SOCKS" https://api.ipify.org || true
echo
EOF
  chmod 0755 /usr/local/bin/xray-proxy-test
}

configure_docker_proxy() {
  # If Docker is already installed, configure only the Docker daemon's outbound
  # HTTP(S) requests (image pulls, registry access) through local Xray.
  # Containers themselves do not automatically inherit this proxy.
  if ! command -v docker >/dev/null 2>&1; then
    info "Docker not installed; skipping Docker daemon proxy configuration."
    return
  fi

  info "Configuring Docker daemon to use local Xray HTTP proxy..."
  mkdir -p /etc/systemd/system/docker.service.d
  cat >/etc/systemd/system/docker.service.d/xray-proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
  systemctl daemon-reload
  systemctl restart docker
}

start_and_test() {
  info "Validating Xray configuration..."
  XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" "$XRAY_BIN" run -test -config "$XRAY_CONFIG"

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
  echo "Routing inside Xray:"
  echo "  Private/CN -> DIRECT"
  echo "  Everything else -> VLESS"
  echo

  info "Testing proxy public IP..."
  PROXY_IP="$(curl -4fsS --max-time 20 --socks5-hostname 127.0.0.1:10808 https://api.ipify.org || true)"
  echo "  Proxy IP: ${PROXY_IP:-<failed>}"

  info "Testing GitHub through proxy..."
  GITHUB_STATUS="$(curl -o /dev/null -sS -w '%{http_code}' --max-time 20 --socks5-hostname 127.0.0.1:10808 https://github.com/ || true)"
  echo "  GitHub HTTP status: ${GITHUB_STATUS:-<failed>}"

  info "Testing Google through proxy..."
  GOOGLE_STATUS="$(curl -o /dev/null -sS -w '%{http_code}' --max-time 20 --socks5-hostname 127.0.0.1:10808 https://www.google.com/ || true)"
  echo "  Google HTTP status: ${GOOGLE_STATUS:-<failed>}"

  if [[ -n "$PROXY_IP" && "$GITHUB_STATUS" =~ ^(200|301|302)$ && "$GOOGLE_STATUS" =~ ^(200|301|302)$ ]]; then
    echo
    echo "SUCCESS: Xray VLESS path, GitHub and Google access are working."
  else
    echo
    echo "WARNING: one or more proxy checks failed."
    echo "Check: journalctl -u xray -n 100 --no-pager"
  fi

  echo
  echo "Shell helpers (open a new shell, or run: source /etc/profile.d/xray-proxy.sh):"
  echo "  proxy_on            enable HTTP(S)/SOCKS proxy vars for current shell"
  echo "  proxy_off           clear proxy vars for current shell"
  echo "  xray-proxy-test     quick connectivity test"
  echo
  echo "Note: ping uses ICMP and does NOT go through this SOCKS/HTTP proxy."
}

install_deps
install_xray
make_config
install_proxy_helpers
start_and_test
configure_docker_proxy
