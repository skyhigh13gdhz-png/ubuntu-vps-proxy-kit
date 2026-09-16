#!/usr/bin/env bash
set -Eeuo pipefail

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
LOG_FILE="/tmp/xray-vless-install.log"

ok(){ printf '[✓] %s\n' "$*"; }
info(){ printf '[→] %s\n' "$*"; }
warn(){ printf '[!] %s\n' "$*" >&2; }
die(){ printf '[✗] %s\n' "$*" >&2; [[ -s "$LOG_FILE" ]] && { printf '[→] 最近安装日志：\n' >&2; tail -n 25 "$LOG_FILE" >&2; }; exit 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die '请使用 sudo/root 运行。'
[[ $# -eq 0 ]] || die '为避免节点凭据进入命令历史，请不要把 VLESS 链接作为命令参数。'

cat <<'EOF'

========== 配置海外网络 ==========

接下来需要填写你的 VLESS 节点链接，格式以 vless:// 开头。
[!] 节点链接包含敏感信息，只保存在当前服务器本地，不会写入 Git。
[!] 为保护隐私，粘贴后屏幕不会显示内容；粘贴完成后直接按 Enter。
EOF
printf '\nVLESS 节点链接：'
read -r -s VLESS_URI
echo
[[ "$VLESS_URI" == vless://* ]] || die '节点链接格式不正确：必须以 vless:// 开头。'

run_quiet(){ local label="$1"; shift; info "$label……"; : >"$LOG_FILE"; if "$@" >"$LOG_FILE" 2>&1; then ok "$label：完成"; else die "$label：失败"; fi; }
install_deps_impl(){ if command -v apt-get >/dev/null 2>&1; then apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates python3 jq unzip git; elif command -v dnf >/dev/null 2>&1; then dnf install -y curl ca-certificates python3 jq unzip git; elif command -v yum >/dev/null 2>&1; then yum install -y curl ca-certificates python3 jq unzip git; else return 127; fi; }
install_deps(){ run_quiet '准备基础工具' install_deps_impl; }
get_arch_asset(){ case "$(uname -m)" in x86_64|amd64) echo Xray-linux-64.zip;; aarch64|arm64) echo Xray-linux-arm64-v8a.zip;; armv7l|armv7) echo Xray-linux-arm32-v7a.zip;; *) die "暂不支持 CPU 架构：$(uname -m)";; esac; }
download_xray_from_gitee(){ local version="$1" asset="$2" output="$3" clone_dir="${XRAY_TMP_DIR}/gitee-xray-bin"; rm -rf "$clone_dir"; git -c advice.detachedHead=false clone --quiet --depth 1 --single-branch --branch "$version" "$XRAY_GITEE_REPO" "$clone_dir" || { rm -rf "$clone_dir"; return 1; }; [[ -f "${clone_dir}/${asset}" ]] || { rm -rf "$clone_dir"; return 1; }; cp -f "${clone_dir}/${asset}" "$output"; if [[ -f "${clone_dir}/${asset}.dgst" ]]; then local expected actual; expected="$(awk -F '= ' '/256=/{print $2; exit}' "${clone_dir}/${asset}.dgst"|tr -d '[:space:]')"; actual="$(sha256sum "$output"|awk '{print $1}')"; [[ -z "$expected" || "$expected" == "$actual" ]] || { rm -rf "$clone_dir" "$output"; return 1; }; fi; rm -rf "$clone_dir"; unzip -tq "$output" >/dev/null || { rm -f "$output"; return 1; }; }
download_xray_fallback(){ local version="$1" asset="$2" output="$3" mirror github_url="${XRAY_GITHUB_DOWNLOAD_BASE}/${version}/${asset}" sourceforge_url="${XRAY_SOURCEFORGE_BASE}/${version}/${asset}/download"; curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 "$sourceforge_url" -o "$output" && unzip -tq "$output" >/dev/null && return 0; rm -f "$output"; for mirror in "${XRAY_MIRRORS[@]}"; do curl -fL --retry 1 --connect-timeout 6 --speed-time 15 --speed-limit 20480 "${mirror}${github_url}" -o "$output" && unzip -tq "$output" >/dev/null && return 0; rm -f "$output"; done; curl -fL --retry 1 --connect-timeout 8 --speed-time 20 --speed-limit 10240 "$github_url" -o "$output" && unzip -tq "$output" >/dev/null; }
install_xray_impl(){ local need=0; [[ -x "$XRAY_BIN" ]]||need=1; [[ -f "$XRAY_ASSET_DIR/geoip.dat" ]]||need=1; [[ -f "$XRAY_ASSET_DIR/geosite.dat" ]]||need=1; ((need))||return 0; local asset zip_file; asset="$(get_arch_asset)"; rm -rf "$XRAY_TMP_DIR"; mkdir -p "$XRAY_TMP_DIR"; zip_file="${XRAY_TMP_DIR}/${asset}"; download_xray_from_gitee "$XRAY_VERSION" "$asset" "$zip_file" || download_xray_fallback "$XRAY_VERSION" "$asset" "$zip_file" || return 1; unzip -oq "$zip_file" -d "$XRAY_TMP_DIR"; install -m0755 "${XRAY_TMP_DIR}/xray" "$XRAY_BIN"; mkdir -p "$XRAY_ASSET_DIR"; install -m0644 "${XRAY_TMP_DIR}/geoip.dat" "$XRAY_ASSET_DIR/geoip.dat"; install -m0644 "${XRAY_TMP_DIR}/geosite.dat" "$XRAY_ASSET_DIR/geosite.dat"; rm -rf "$XRAY_TMP_DIR"; }
install_xray(){ run_quiet '安装/检查 Xray' install_xray_impl; }
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
install_proxy_helpers(){ cat >"$XRAY_PROFILE" <<'EOF'
proxy_on() { export http_proxy="http://127.0.0.1:10809" https_proxy="http://127.0.0.1:10809"; export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"; export ALL_PROXY="socks5h://127.0.0.1:10808" all_proxy="$ALL_PROXY"; export NO_PROXY="localhost,127.0.0.1,::1" no_proxy="$NO_PROXY"; echo "当前 Shell 已启用 Xray 代理。"; }
proxy_off() { unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy; echo "当前 Shell 代理变量已清除。"; }
xray_return_cleanup() { proxy_off >/dev/null 2>&1 || true; if [[ -n "${BASH_VERSION:-}" ]]; then local _ids=() _id; while IFS= read -r _id; do [[ -n "$_id" ]] && _ids+=("$_id"); done < <(builtin history | awk 'tolower($0) ~ /vless:\/\// {print $1}' | sort -rn); for _id in "${_ids[@]}"; do builtin history -d "$_id" 2>/dev/null || true; done; builtin history -w 2>/dev/null || true; fi; sudo xray-vless-manager uninstall --purge-history; }
EOF
chmod 0644 "$XRAY_PROFILE"; local target_user="${SUDO_USER:-root}" target_home; target_home="$(getent passwd "$target_user" | cut -d: -f6)"; if [[ -n "$target_home" && -d "$target_home" ]]; then local bashrc="${target_home}/.bashrc" marker='# memory-server-infra: xray proxy helpers'; touch "$bashrc"; if ! grep -Fq "$marker" "$bashrc"; then printf '\n%s\n[ -r /etc/profile.d/xray-proxy.sh ] && . /etc/profile.d/xray-proxy.sh\n' "$marker" >>"$bashrc"; chown "$target_user":"$(id -gn "$target_user")" "$bashrc" 2>/dev/null || true; fi; fi; }
fetch_small_tool(){ local name="$1" output="$2" url="${TOOLS_RAW_BASE}/$1" mirror; curl -fsSL --connect-timeout 6 --max-time 20 "$url" -o "$output" && return; rm -f "$output"; for mirror in "${XRAY_MIRRORS[@]}"; do curl -fsSL --connect-timeout 6 --max-time 20 "${mirror}${url}" -o "$output" && return; rm -f "$output"; done; return 1; }
install_repo_tool(){ local name="$1" target="$2" source="${SCRIPT_DIR}/$1" tmp; if [[ -f "$source" ]];then install -m0755 "$source" "$target";return;fi; tmp="$(mktemp)"; fetch_small_tool "$name" "$tmp"&&{ install -m0755 "$tmp" "$target";rm -f "$tmp";return;};rm -f "$tmp";[[ -x "$target" ]]||die "无法安装辅助工具：$name"; }
install_management_tools(){ mkdir -p "$XRAY_LIBEXEC_DIR"; install -m0700 "$0" "$XRAY_BOOTSTRAP"; install_repo_tool xray-vless-manager "$XRAY_MANAGER"; install_repo_tool xray-proxy-test "$XRAY_TEST"; }
configure_docker_proxy(){ command -v docker >/dev/null 2>&1||return 0; mkdir -p "$(dirname "$DOCKER_PROXY_FILE")"; cat >"$DOCKER_PROXY_FILE" <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
systemctl daemon-reload;systemctl restart docker; }
start_xray(){ XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" "$XRAY_BIN" run -test -config "$XRAY_CONFIG" >/dev/null; systemctl enable --now xray >/dev/null; sleep 2; systemctl is-active --quiet xray; }

install_deps
install_xray
info '正在写入本机 Xray 配置……'; ensure_service; make_config; install_proxy_helpers; install_management_tools; ok '本机 Xray 配置：完成'
run_quiet '启动 Xray 服务' start_xray
run_quiet '配置 Docker 出站' configure_docker_proxy
rm -f "$LOG_FILE"
echo
"$XRAY_TEST" || die '海外网络验收失败。'
echo
info '后续无需让整个 Shell 常驻代理；Memory Server 会按服务范围单独配置网络。'
