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
XRAY_MIRRORS=("https://gh.ddlc.top/" "https://ghproxy.net/")
TOOLS_RAW_BASE="https://raw.githubusercontent.com/skyhigh13gdhz-png/ubuntu-vps-proxy-kit/mainland_vps_use_proxy"

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[+] $*"; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Please run as root (sudo)."
[[ $# -eq 0 ]] || die "For security, do not pass a VLESS URI on the command line. Run this script with no arguments and paste it into the hidden prompt."
read -r -s -p "Paste VLESS URI: " VLESS_URI; echo
[[ "$VLESS_URI" == vless://* ]] || die "The VLESS URI must start with vless://"

install_deps(){
  if command -v apt-get >/dev/null 2>&1; then apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates python3 jq unzip git
  elif command -v dnf >/dev/null 2>&1; then dnf install -y curl ca-certificates python3 jq unzip git
  elif command -v yum >/dev/null 2>&1; then yum install -y curl ca-certificates python3 jq unzip git
  else die "Unsupported distro: apt/dnf/yum not found."; fi
}
get_arch_asset(){ case "$(uname -m)" in x86_64|amd64) echo Xray-linux-64.zip;; aarch64|arm64) echo Xray-linux-arm64-v8a.zip;; armv7l|armv7) echo Xray-linux-arm32-v7a.zip;; *) die "Unsupported CPU architecture: $(uname -m)";; esac; }
download_xray_from_gitee(){ local version="$1" asset="$2" output="$3" clone_dir="${XRAY_TMP_DIR}/gitee-xray-bin"; info "Trying mainland Gitee binary mirror (${version})..."; rm -rf "$clone_dir"; git -c advice.detachedHead=false clone --quiet --depth 1 --single-branch --branch "$version" "$XRAY_GITEE_REPO" "$clone_dir" || { rm -rf "$clone_dir"; return 1; }; [[ -f "${clone_dir}/${asset}" ]] || { rm -rf "$clone_dir"; return 1; }; cp -f "${clone_dir}/${asset}" "$output"; if [[ -f "${clone_dir}/${asset}.dgst" ]]; then local expected actual; expected="$(awk -F '= ' '/256=/{print $2; exit}' "${clone_dir}/${asset}.dgst"|tr -d '[:space:]')"; actual="$(sha256sum "$output"|awk '{print $1}')"; [[ -z "$expected" || "$expected" == "$actual" ]] || { rm -rf "$clone_dir" "$output"; return 1; }; fi; rm -rf "$clone_dir"; unzip -tq "$output" >/dev/null || { rm -f "$output"; return 1; }; }
download_xray_fallback(){ local version="$1" asset="$2" output="$3" mirror github_url="${XRAY_GITHUB_DOWNLOAD_BASE}/${version}/${asset}" sourceforge_url="${XRAY_SOURCEFORGE_BASE}/${version}/${asset}/download"; curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 "$sourceforge_url" -o "$output" && unzip -tq "$output" >/dev/null && return 0; rm -f "$output"; for mirror in "${XRAY_MIRRORS[@]}"; do curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 "${mirror}${github_url}" -o "$output" && unzip -tq "$output" >/dev/null && return 0; rm -f "$output"; done; curl -fL --retry 1 --connect-timeout 8 --speed-time 20 --speed-limit 10240 "$github_url" -o "$output" && unzip -tq "$output" >/dev/null; }
install_xray(){ local need=0; [[ -x "$XRAY_BIN" ]]||need=1; [[ -f "$XRAY_ASSET_DIR/geoip.dat" ]]||need=1; [[ -f "$XRAY_ASSET_DIR/geosite.dat" ]]||need=1; ((need))||{ info "Xray already installed: $($XRAY_BIN version|head -n1)"; return; }; local asset zip_file; asset="$(get_arch_asset)"; rm -rf "$XRAY_TMP_DIR"; mkdir -p "$XRAY_TMP_DIR"; zip_file="${XRAY_TMP_DIR}/${asset}"; download_xray_from_gitee "$XRAY_VERSION" "$asset" "$zip_file" || download_xray_fallback "$XRAY_VERSION" "$asset" "$zip_file" || die "Failed to download Xray."; unzip -oq "$zip_file" -d "$XRAY_TMP_DIR"; install -m0755 "${XRAY_TMP_DIR}/xray" "$XRAY_BIN"; mkdir -p "$XRAY_ASSET_DIR"; install -m0644 "${XRAY_TMP_DIR}/geoip.dat" "$XRAY_ASSET_DIR/geoip.dat"; install -m0644 "${XRAY_TMP_DIR}/geosite.dat" "$XRAY_ASSET_DIR/geosite.dat"; rm -rf "$XRAY_TMP_DIR"; }
ensure_service(){ cat >/etc/systemd/system/xray.service <<'EOF'
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
systemctl daemon-reload; }
make_config(){ mkdir -p "$(dirname "$XRAY_CONFIG")"; find "$(dirname "$XRAY_CONFIG")" -maxdepth 1 -type f -name 'config.json.bak.*' -delete 2>/dev/null||true; VLESS_URI="$VLESS_URI" python3 - "$XRAY_CONFIG" <<'PY'
import json,os,sys
from urllib.parse import urlsplit,parse_qs,unquote
u=urlsplit(os.environ['VLESS_URI']); q={k:v[-1] for k,v in parse_qs(u.query,keep_blank_values=True).items()}; uuid=unquote(u.username or ''); host=u.hostname; port=u.port
if u.scheme.lower()!='vless' or not uuid or not host or not port: raise SystemExit('Invalid VLESS URI')
network=(q.get('type') or 'tcp').lower(); security=(q.get('security') or 'none').lower(); user={'id':uuid,'encryption':q.get('encryption') or 'none'}
if q.get('flow'): user['flow']=q['flow']
stream={'network':network,'security':security}
if security=='reality':
 r={}; sni=q.get('sni') or q.get('serverName');
 if sni:r['serverName']=sni
 if q.get('fp'):r['fingerprint']=q['fp']
 if q.get('pbk') or q.get('publicKey'):r['publicKey']=q.get('pbk') or q.get('publicKey')
 if q.get('sid') or q.get('shortId'):r['shortId']=q.get('sid') or q.get('shortId')
 stream['realitySettings']=r
elif security=='tls':
 t={}; sni=q.get('sni') or q.get('serverName');
 if sni:t['serverName']=sni
 if q.get('fp'):t['fingerprint']=q['fp']
 stream['tlsSettings']=t
if network=='ws': stream['wsSettings']={k:v for k,v in {'path':q.get('path')}.items() if v}
elif network=='grpc': stream['grpcSettings']={k:v for k,v in {'serviceName':q.get('serviceName') or q.get('path')}.items() if v}
elif network=='xhttp': stream['xhttpSettings']={k:v for k,v in {'path':q.get('path'),'host':q.get('host'),'mode':q.get('mode')}.items() if v}
cfg={'log':{'loglevel':'warning'},'inbounds':[{'tag':'socks-local','listen':'127.0.0.1','port':10808,'protocol':'socks','settings':{'udp':True}},{'tag':'http-local','listen':'127.0.0.1','port':10809,'protocol':'http','settings':{}}],'outbounds':[{'tag':'overseas','protocol':'vless','settings':{'vnext':[{'address':host,'port':port,'users':[user]}]},'streamSettings':stream},{'tag':'direct','protocol':'freedom'},{'tag':'block','protocol':'blackhole'}],'routing':{'domainStrategy':'IPIfNonMatch','rules':[{'type':'field','ip':['geoip:private','geoip:cn'],'outboundTag':'direct'},{'type':'field','domain':['geosite:cn'],'outboundTag':'direct'}]}}
with open(sys.argv[1],'w') as f:json.dump(cfg,f,indent=2)
PY
chmod 600 "$XRAY_CONFIG"; unset VLESS_URI; }

install_proxy_helpers(){
  cat >"$XRAY_PROFILE" <<'EOF'
# Xray shell helpers. Loading this file NEVER enables the proxy automatically.
proxy_on() {
  export http_proxy="http://127.0.0.1:10809" https_proxy="http://127.0.0.1:10809"
  export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"
  export ALL_PROXY="socks5h://127.0.0.1:10808" all_proxy="$ALL_PROXY"
  export NO_PROXY="localhost,127.0.0.1,::1" no_proxy="$NO_PROXY"
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
    while IFS= read -r _id; do [[ -n "$_id" ]] && _ids+=("$_id"); done < <(builtin history | awk 'tolower($0) ~ /vless:\/\// {print $1}' | sort -rn)
    for _id in "${_ids[@]}"; do builtin history -d "$_id" 2>/dev/null || true; done
    builtin history -w 2>/dev/null || true
  fi
  sudo xray-vless-manager uninstall --purge-history
}
EOF
  chmod 0644 "$XRAY_PROFILE"

  # /etc/profile.d 通常只由 login shell 读取。腾讯云等环境的 SSH Bash 可能只读取 ~/.bashrc。
  # 因此给实际 sudo 调用者的 ~/.bashrc 安装一个幂等 loader；只加载函数，绝不会自动 proxy_on。
  local target_user="${SUDO_USER:-root}" target_home
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  if [[ -n "$target_home" && -d "$target_home" ]]; then
    local bashrc="${target_home}/.bashrc" marker='# memory-server-infra: xray proxy helpers'
    touch "$bashrc"
    if ! grep -Fq "$marker" "$bashrc"; then
      cat >>"$bashrc" <<EOF

${marker}
[ -r /etc/profile.d/xray-proxy.sh ] && . /etc/profile.d/xray-proxy.sh
EOF
      chown "$target_user":"$(id -gn "$target_user")" "$bashrc" 2>/dev/null || true
    fi
  fi
}
fetch_small_tool(){ local name="$1" output="$2" url="${TOOLS_RAW_BASE}/$1" mirror; curl -fsSL --connect-timeout 6 --max-time 20 "$url" -o "$output" && return; rm -f "$output"; for mirror in "${XRAY_MIRRORS[@]}"; do curl -fsSL --connect-timeout 6 --max-time 20 "${mirror}${url}" -o "$output" && return; rm -f "$output"; done; return 1; }
install_repo_tool(){ local name="$1" target="$2" source="${SCRIPT_DIR}/$1" tmp; if [[ -f "$source" ]];then install -m0755 "$source" "$target";return;fi; tmp="$(mktemp)"; fetch_small_tool "$name" "$tmp"&&{ install -m0755 "$tmp" "$target";rm -f "$tmp";return;};rm -f "$tmp";[[ -x "$target" ]]||die "Could not install $name."; }
install_management_tools(){ mkdir -p "$XRAY_LIBEXEC_DIR"; install -m0700 "$0" "$XRAY_BOOTSTRAP"; install_repo_tool xray-vless-manager "$XRAY_MANAGER"; install_repo_tool xray-proxy-test "$XRAY_TEST"; }
configure_docker_proxy(){ command -v docker >/dev/null 2>&1||{ info "Docker not installed; skipping Docker daemon proxy configuration.";return;}; mkdir -p "$(dirname "$DOCKER_PROXY_FILE")"; cat >"$DOCKER_PROXY_FILE" <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
systemctl daemon-reload;systemctl restart docker; }
start_and_test(){ XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" "$XRAY_BIN" run -test -config "$XRAY_CONFIG"; systemctl enable --now xray;sleep 2;systemctl is-active --quiet xray||die "Xray failed to start."; "$XRAY_TEST"||true; }

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
echo
echo "Shell helper note:"
echo "  New SSH/Bash sessions will have proxy_on/proxy_off available but proxy remains OFF by default."
echo "  For this already-open shell, run: source /etc/profile.d/xray-proxy.sh"
