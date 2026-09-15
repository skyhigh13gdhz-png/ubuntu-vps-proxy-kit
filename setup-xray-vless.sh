#!/usr/bin/env bash
set -Eeuo pipefail

# Mainland VPS -> local Xray client -> overseas VLESS node.
# Security rule: VLESS credentials are accepted only through hidden interactive input.

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_TMP_DIR="/tmp/xray-bootstrap"
XRAY_LIBEXEC_DIR="/usr/local/libexec/xray-vless"
XRAY_BOOTSTRAP="${XRAY_LIBEXEC_DIR}/setup-xray-vless.sh"
XRAY_MANAGER="/usr/local/bin/xray-vless-manager"
XRAY_TEST="/usr/local/bin/xray-proxy-test"
XRAY_PROFILE="/etc/profile.d/xray-proxy.sh"
DOCKER_PROXY_FILE="/etc/systemd/system/docker.service.d/xray-proxy.conf"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"

XRAY_VERSION="${XRAY_VERSION:-v26.3.27}"
XRAY_GITEE_REPO="https://gitee.com/skyhigh13/xray_bin.git"
XRAY_GITHUB_DOWNLOAD_BASE="https://github.com/XTLS/Xray-core/releases/download"
XRAY_SOURCEFORGE_BASE="https://sourceforge.net/projects/xray-core.mirror/files"
XRAY_MIRRORS=(
  "https://gh.ddlc.top/"
  "https://ghproxy.net/"
)
TOOLS_RAW_BASE="https://raw.githubusercontent.com/skyhigh13gdhz-png/ubuntu-vps-proxy-kit/mainland_vps_use_proxy"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[+] $*"; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Please run as root (sudo)."

if [[ $# -gt 0 ]]; then
  die "For security, do not pass a VLESS URI on the command line. Run this script with no arguments and paste it into the hidden prompt."
fi
read -r -s -p "Paste VLESS URI: " VLESS_URI
echo
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
  if ! git -c advice.detachedHead=false clone --quiet --depth 1 --single-branch --branch "$version" "$XRAY_GITEE_REPO" "$clone_dir"; then
    rm -rf "$clone_dir"; return 1
  fi
  [[ -f "${clone_dir}/${asset}" ]] || { rm -rf "$clone_dir"; return 1; }
  cp -f "${clone_dir}/${asset}" "$output"
  if [[ -f "${clone_dir}/${asset}.dgst" ]]; then
    local expected actual
    expected="$(awk -F '= ' '/256=/{print $2; exit}' "${clone_dir}/${asset}.dgst" | tr -d '[:space:]')"
    actual="$(sha256sum "$output" | awk '{print $1}')"
    [[ -z "$expected" || "$expected" == "$actual" ]] || { rm -rf "$clone_dir" "$output"; return 1; }
    [[ -n "$expected" ]] && info "SHA256 verification passed."
  fi
  rm -rf "$clone_dir"
  unzip -tq "$output" >/dev/null || { rm -f "$output"; return 1; }
  info "Downloaded ${asset} from Gitee successfully."
}

download_xray_fallback() {
  local version="$1" asset="$2" output="$3" mirror
  local github_url="${XRAY_GITHUB_DOWNLOAD_BASE}/${version}/${asset}"
  local sourceforge_url="${XRAY_SOURCEFORGE_BASE}/${version}/${asset}/download"
  info "Gitee unavailable; trying SourceForge fallback..."
  if curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 "$sourceforge_url" -o "$output"; then
    unzip -tq "$output" >/dev/null && return 0
  fi
  rm -f "$output"
  for mirror in "${XRAY_MIRRORS[@]}"; do
    info "Trying GitHub fallback mirror: $mirror"
    if curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 "${mirror}${github_url}" -o "$output"; then
      unzip -tq "$output" >/dev/null && return 0
    fi
    rm -f "$output"
  done
  info "Trying official GitHub as final fallback..."
  if curl -fL --retry 1 --connect-timeout 8 --speed-time 20 --speed-limit 10240 "$github_url" -o "$output"; then
    unzip -tq "$output" >/dev/null && return 0
  fi
  rm -f "$output"; return 1
}

install_xray() {
  local need_install=0
  [[ -x "$XRAY_BIN" ]] || need_install=1
  [[ -f "$XRAY_ASSET_DIR/geoip.dat" ]] || need_install=1
  [[ -f "$XRAY_ASSET_DIR/geosite.dat" ]] || need_install=1
  if [[ "$need_install" -eq 0 ]]; then
    info "Xray already installed: $($XRAY_BIN version | head -n1)"
    return
  fi
  local asset version zip_file
  asset="$(get_arch_asset)"; version="$XRAY_VERSION"
  rm -rf "$XRAY_TMP_DIR"; mkdir -p "$XRAY_TMP_DIR"
  zip_file="${XRAY_TMP_DIR}/${asset}"
  info "Installing Xray ${version} (${asset})..."
  if ! download_xray_from_gitee "$version" "$asset" "$zip_file"; then
    download_xray_fallback "$version" "$asset" "$zip_file" || die "Failed to download Xray from Gitee and all fallback sources."
  fi
  unzip -tq "$zip_file" >/dev/null || die "Downloaded Xray archive is corrupt."
  unzip -oq "$zip_file" -d "$XRAY_TMP_DIR"
  [[ -f "${XRAY_TMP_DIR}/xray" ]] || die "Xray binary missing from archive."
  install -m 0755 "${XRAY_TMP_DIR}/xray" "$XRAY_BIN"
  mkdir -p "$XRAY_ASSET_DIR"
  [[ -f "${XRAY_TMP_DIR}/geoip.dat" ]] && install -m 0644 "${XRAY_TMP_DIR}/geoip.dat" "$XRAY_ASSET_DIR/geoip.dat"
  [[ -f "${XRAY_TMP_DIR}/geosite.dat" ]] && install -m 0644 "${XRAY_TMP_DIR}/geosite.dat" "$XRAY_ASSET_DIR/geosite.dat"
  rm -rf "$XRAY_TMP_DIR"
  info "Xray installed successfully: $($XRAY_BIN version | head -n1)"
}

ensure_service() {
  cat >/etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
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
}

remove_old_sensitive_backups() {
  local dir="$(dirname "$XRAY_CONFIG")"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name 'config.json.bak.*' -delete 2>/dev/null || true
}

make_config() {
  mkdir -p "$(dirname "$XRAY_CONFIG")"
  remove_old_sensitive_backups
  VLESS_URI="$VLESS_URI" python3 - "$XRAY_CONFIG" <<'PY'
import json, os, sys
from urllib.parse import urlsplit, parse_qs, unquote
uri=os.environ["VLESS_URI"]; out=sys.argv[1]; u=urlsplit(uri)
if u.scheme.lower()!="vless": raise SystemExit("Not a VLESS URI")
uuid=unquote(u.username or ""); host=u.hostname; port=u.port
if not uuid or not host or not port: raise SystemExit("VLESS URI is missing UUID, host, or port")
q={k:v[-1] for k,v in parse_qs(u.query,keep_blank_values=True).items()}
network=(q.get("type") or "tcp").lower(); security=(q.get("security") or "none").lower()
user={"id":uuid,"encryption":q.get("encryption") or "none"}
if q.get("flow"): user["flow"]=q["flow"]
stream={"network":network,"security":security}
if security=="tls":
    tls={}; sni=q.get("sni") or q.get("serverName")
    if sni: tls["serverName"]=sni
    if q.get("fp"): tls["fingerprint"]=q["fp"]
    if q.get("alpn"): tls["alpn"]=[x for x in q["alpn"].split(",") if x]
    if (q.get("allowInsecure") or "").lower() in ("1","true","yes"): tls["allowInsecure"]=True
    stream["tlsSettings"]=tls
elif security=="reality":
    r={}; sni=q.get("sni") or q.get("serverName")
    if sni: r["serverName"]=sni
    if q.get("fp"): r["fingerprint"]=q["fp"]
    pbk=q.get("pbk") or q.get("publicKey"); sid=q.get("sid") or q.get("shortId"); spx=q.get("spx") or q.get("spiderX")
    if pbk: r["publicKey"]=pbk
    if sid: r["shortId"]=sid
    if spx: r["spiderX"]=spx
    stream["realitySettings"]=r
if network=="ws":
    ws={}
    if q.get("path"): ws["path"]=q["path"]
    if q.get("host"): ws["headers"]={"Host":q["host"]}
    stream["wsSettings"]=ws
elif network=="grpc":
    g={}; service=q.get("serviceName") or q.get("path")
    if service: g["serviceName"]=service
    if q.get("authority"): g["authority"]=q["authority"]
    if (q.get("mode") or "").lower()=="multi": g["multiMode"]=True
    stream["grpcSettings"]=g
elif network=="xhttp":
    x={}
    if q.get("path"): x["path"]=q["path"]
    if q.get("host"): x["host"]=q["host"]
    if q.get("mode"): x["mode"]=q["mode"]
    stream["xhttpSettings"]=x
config={"log":{"loglevel":"warning"},"inbounds":[{"tag":"socks-local","listen":"127.0.0.1","port":10808,"protocol":"socks","settings":{"udp":True}},{"tag":"http-local","listen":"127.0.0.1","port":10809,"protocol":"http","settings":{}}],"outbounds":[{"tag":"overseas","protocol":"vless","settings":{"vnext":[{"address":host,"port":port,"users":[user]}]},"streamSettings":stream},{"tag":"direct","protocol":"freedom"},{"tag":"block","protocol":"blackhole"}],"routing":{"domainStrategy":"IPIfNonMatch","rules":[{"type":"field","ip":["geoip:private","geoip:cn"],"outboundTag":"direct"},{"type":"field","domain":["geosite:cn"],"outboundTag":"direct"}]}}
with open(out,"w",encoding="utf-8") as f: json.dump(config,f,ensure_ascii=False,indent=2)
print(f"Parsed VLESS: host={host}, port={port}, network={network}, security={security}")
PY
  chmod 600 "$XRAY_CONFIG"
}

install_proxy_helpers() {
  cat >"$XRAY_PROFILE" <<'EOF'
proxy_on() {
  export http_proxy="http://127.0.0.1:10809" https_proxy="http://127.0.0.1:10809"
  export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"
  export ALL_PROXY="socks5h://127.0.0.1:10808" all_proxy="socks5h://127.0.0.1:10808"
  export NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1"
  echo "Xray proxy enabled for this shell."
}
proxy_off() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy
  echo "Proxy variables cleared for this shell."
}
xray_return_cleanup() {
  proxy_off >/dev/null 2>&1 || true
  if [[ -n "${BASH_VERSION:-}" ]]; then
    local _ids=() _id
    while IFS= read -r _id; do
      [[ -n "$_id" ]] && _ids+=("$_id")
    done < <(builtin history | awk 'tolower($0) ~ /vless:\/\// {print $1}' | sort -rn)
    for _id in "${_ids[@]}"; do builtin history -d "$_id" 2>/dev/null || true; done
    builtin history -w 2>/dev/null || true
  fi
  sudo xray-vless-manager uninstall --purge-history
}
EOF
  chmod 0644 "$XRAY_PROFILE"
}

fetch_small_tool() {
  local name="$1"
  local output="$2"
  local url="${TOOLS_RAW_BASE}/${name}"
  local mirror
  if curl -fsSL --connect-timeout 6 --max-time 20 "$url" -o "$output"; then return 0; fi
  rm -f "$output"
  for mirror in "${XRAY_MIRRORS[@]}"; do
    if curl -fsSL --connect-timeout 6 --max-time 20 "${mirror}${url}" -o "$output"; then return 0; fi
    rm -f "$output"
  done
  return 1
}

install_repo_tool() {
  local name="$1"
  local target="$2"
  local source="${SCRIPT_DIR}/${name}"
  local tmp
  if [[ -f "$source" ]]; then
    install -m 0755 "$source" "$target"; return 0
  fi
  tmp="$(mktemp)"
  if fetch_small_tool "$name" "$tmp"; then
    install -m 0755 "$tmp" "$target"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  if [[ -x "$target" ]]; then
    info "Could not refresh ${name}; keeping the already installed helper."
    return 0
  fi
  die "Could not install ${name}. Run the installer from a full clone of this repository."
}

install_management_tools() {
  mkdir -p "$XRAY_LIBEXEC_DIR"
  install -m 0700 "$0" "$XRAY_BOOTSTRAP"
  install_repo_tool "xray-vless-manager" "$XRAY_MANAGER"
  install_repo_tool "xray-proxy-test" "$XRAY_TEST"
}

configure_docker_proxy() {
  if ! command -v docker >/dev/null 2>&1; then info "Docker not installed; skipping Docker daemon proxy configuration."; return; fi
  info "Configuring Docker daemon to use local Xray HTTP proxy..."
  mkdir -p "$(dirname "$DOCKER_PROXY_FILE")"
  cat >"$DOCKER_PROXY_FILE" <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
  systemctl daemon-reload; systemctl restart docker
}

start_and_test() {
  info "Validating Xray configuration..."
  XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" "$XRAY_BIN" run -test -config "$XRAY_CONFIG"
  systemctl enable --now xray; sleep 2
  systemctl is-active --quiet xray || { systemctl status xray --no-pager -l || true; journalctl -u xray -n 80 --no-pager || true; die "Xray failed to start."; }
  info "Xray is running."
  "$XRAY_TEST" || true
}

install_deps
install_xray
ensure_service
make_config
install_proxy_helpers
install_management_tools
start_and_test
configure_docker_proxy

echo
echo "Daily commands:"
echo "  xray-vless-manager status"
echo "  xray-vless-manager test"
echo "  proxy_on / proxy_off"
echo "  sudo xray-vless-manager set-node"
echo "  sudo xray-vless-manager remove-node"
echo "  xray_return_cleanup   # before returning/transferring this VPS"
