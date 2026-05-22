#!/usr/bin/env bash
# Verify kill-switch design: VPN-only internet, HTTP proxy, ngrok bridge path.
# Run: sudo ./tests/verify-killswitch-features.sh
set -euo pipefail

PODMAN=(sudo podman)
CONTAINER=work_container
PROXY_PORT="${WORK_CONTAINER_NODE_PROXY_PORT:-3128}"
FAIL=0

pass() { printf 'OK  %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAIL=1; }

if ! "${PODMAN[@]}" ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  echo "Container ${CONTAINER} is not running." >&2
  exit 1
fi

section() { printf '\n=== %s ===\n' "$1"; }

section "Kill-switch rules present"
"${PODMAN[@]}" exec "${CONTAINER}" sh -c '
  iptables -L OUTPUT -n | grep -q "policy match dir out pol ipsec" || exit 1
  iptables -L INPUT -n | grep -q "policy match dir in pol ipsec" || exit 1
  iptables -L INPUT -n | grep -q "dpt:'"${PROXY_PORT}"'" || exit 1
  GW=$(ip route | awk "/default/ {print \$3; exit}")
  iptables -L OUTPUT -n | grep -Fq "${GW}" || exit 1
' && pass "ipsec policy + proxy port + bridge gateway OUTPUT" || fail "iptables rules"

section "VPN + DNS"
if "${PODMAN[@]}" exec "${CONTAINER}" getent ahostsv4 one.one.one.one >/dev/null 2>&1; then
  pass "DNS through tunnel"
else
  fail "DNS through tunnel"
fi

VPN_IP="$("${PODMAN[@]}" exec "${CONTAINER}" curl -4 -fsS --max-time 15 https://ifconfig.me/ip 2>/dev/null || true)"
if [[ -n "${VPN_IP}" ]]; then
  pass "container egress via VPN (${VPN_IP})"
else
  fail "container egress via VPN"
fi

section "HTTP proxy (host -> tinyproxy -> VPN)"
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "127.0.0.1:${PROXY_PORT}$"; then
  pass "proxy listening on 127.0.0.1:${PROXY_PORT}"
else
  fail "proxy not listening on host"
fi

PROXY_IP="$(curl -4 -fsS --max-time 20 --proxy "http://127.0.0.1:${PROXY_PORT}" https://ifconfig.me/ip 2>/dev/null || true)"
if [[ -n "${PROXY_IP}" && "${PROXY_IP}" == "${VPN_IP}" ]]; then
  pass "proxy egress matches VPN (${PROXY_IP})"
elif [[ -n "${PROXY_IP}" ]]; then
  fail "proxy egress ${PROXY_IP} != VPN ${VPN_IP}"
else
  fail "proxy request failed"
fi

section "ngrok path (container -> bridge gateway + internet)"
if "${PODMAN[@]}" exec "${CONTAINER}" sh -c '
  GW=$(ip route | awk "/default/ {print \$3}")
  err=$(timeout 2 bash -c "echo >/dev/tcp/${GW}/65530" 2>&1) || true
  echo "$err" | grep -qiE "unreachable|timed out|no route" && exit 1
  exit 0
'; then
  pass "bridge gateway TCP allowed (ngrok backend)"
else
  fail "bridge gateway TCP blocked"
fi

if "${PODMAN[@]}" exec "${CONTAINER}" curl -4 -fsS --max-time 15 -o /dev/null https://ngrok.com/ 2>/dev/null; then
  pass "ngrok cloud reachable via VPN"
else
  fail "ngrok cloud reachable via VPN"
fi

section "ip rule: host gateway stays on main table"
GW="$("${PODMAN[@]}" exec "${CONTAINER}" ip route | awk '/default/ {print $3; exit}')"
if "${PODMAN[@]}" exec "${CONTAINER}" ip rule show | grep -Fq "to ${GW} lookup main"; then
  pass "policy rule for bridge gateway (${GW})"
else
  fail "missing ip rule for bridge gateway (ensure_ip_rule_to_main)"
fi

exit "${FAIL}"
