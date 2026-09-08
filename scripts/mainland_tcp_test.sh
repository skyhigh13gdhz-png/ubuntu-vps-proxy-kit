#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
require_root
require_supported_ubuntu
apt_install_missing netcat-openbsd tcpdump

IPV4="$(public_ipv4)"; IFACE="$(default_iface)"
PORT="${1:-18080}"
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${PORT}$"; then die "Port $PORT is already in use"; fi
LOG="$LOG_DIR/mainland-tcp-${PORT}-$(timestamp).log"
PCAP="$LOG_DIR/mainland-tcp-${PORT}-$(timestamp).pcap"

cleanup(){
  [[ -n "${NC_PID:-}" ]] && kill "$NC_PID" 2>/dev/null || true
  [[ -n "${TCPDUMP_PID:-}" ]] && kill "$TCPDUMP_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

tcpdump -ni "${IFACE:-any}" -w "$PCAP" "tcp port $PORT" >/dev/null 2>&1 & TCPDUMP_PID=$!
# OpenBSD nc handles one connection per invocation; loop for retries.
(
  while true; do
    printf 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK' | nc -l "$PORT" -v >>"$LOG" 2>&1 || true
  done
) & NC_PID=$!
sleep 1
cat <<OUT

Optional Mainland China inbound verification
VPS IPv4: $IPV4
Test URL: http://$IPV4:$PORT/

Turn OFF VPN/proxy on a Mainland China connection and open the URL once.
This is an ADVANCED diagnostic, not a mandatory install step.
Press Enter here after testing.
OUT
read -r _ || true
sleep 1
cleanup
trap - EXIT INT TERM

echo
if grep -Eq 'Connection received|connect to|GET /|Host:' "$LOG" 2>/dev/null; then
  ok "Application-level TCP/HTTP connection reached the VPS"
else
  warn "No application-level connection was recorded"
fi

if [[ -s "$PCAP" ]]; then
  summary="$(tcpdump -nn -r "$PCAP" 2>/dev/null || true)"
  syn_in=$(grep -Ec "> ${IPV4//./\.}\.${PORT}: Flags \[S\]" <<<"$summary" || true)
  synack_out=$(grep -Ec "${IPV4//./\.}\.${PORT} > .*Flags \[S\.\]" <<<"$summary" || true)
  ack_in=$(grep -Ec "> ${IPV4//./\.}\.${PORT}: Flags \[\.\]" <<<"$summary" || true)
  print_kv "Inbound SYN seen" "$syn_in"
  print_kv "Outbound SYN-ACK seen" "$synack_out"
  print_kv "Inbound ACK seen" "$ack_in"
  if ((syn_in>0 && synack_out>0 && ack_in==0)); then
    warn "Pattern resembles SYN received + SYN-ACK sent + no final ACK. Suspect external return-path/filtering/IP reachability before changing Xray/Linux tunables."
  elif ((syn_in==0)); then
    warn "No inbound SYN captured. Check provider cloud firewall/security group, wrong IP/port, or external reachability."
  fi
fi
info "Text log: $LOG"
info "Packet capture: $PCAP"
