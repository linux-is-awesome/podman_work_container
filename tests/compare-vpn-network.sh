#!/usr/bin/env bash
# Compare host vs work_container VPN/network (run: sudo ./tests/compare-vpn-network.sh)
set -euo pipefail

PODMAN=(sudo podman)

section() { printf '\n=== %s ===\n' "$1"; }

section "Host: default route / MTU"
ip -4 route show default
ip -4 link show up | awk '/^[0-9]+:/ {iface=$2; gsub(/:/,"",iface)} /mtu/ {print iface, $0}'

section "Host: strongSwan / IPsec"
if command -v swanctl >/dev/null 2>&1; then
  sudo swanctl --list-sas 2>/dev/null | head -20 || true
fi
if command -v ip >/dev/null 2>&1; then
  ip xfrm policy 2>/dev/null | head -12 || true
  ip xfrm state 2>/dev/null | head -8 || true
fi

section "Host: iptables mangle (informational; stale unused chains are common)"
sudo iptables -t mangle -L -n -v 2>/dev/null | head -20 || echo "(no mangle rules or no permission)"

section "Host: HTTPS smoke"
for u in https://google.com https://www.salesforce.com https://vrpinc.my.site.com/; do
  curl -4 -o /dev/null -s -w "%{url_effective} code=%{http_code} time=%{time_total}s\n" --max-time 25 "$u" || echo "FAIL: $u"
done

if ! "${PODMAN[@]}" ps --format '{{.Names}}' | grep -qx work_container; then
  section "Container"
  echo "work_container is not running — start service first, then re-run."
  exit 0
fi

section "Container: route / MTU"
"${PODMAN[@]}" exec work_container ip -4 route show default
"${PODMAN[@]}" exec work_container ip -4 link show up

section "Container: resolv / swanctl"
"${PODMAN[@]}" exec work_container cat /etc/resolv.conf
"${PODMAN[@]}" exec work_container swanctl --list-sas 2>/dev/null | head -20

section "Container: iptables mangle + filter summary"
"${PODMAN[@]}" exec work_container iptables -t mangle -L -n -v
"${PODMAN[@]}" exec work_container iptables -L OUTPUT -n -v | head -15

section "Container: charon MSS setting"
"${PODMAN[@]}" exec work_container grep -r '^[[:space:]]*mss' /etc/strongswan.d/charon/ 2>/dev/null || true

section "Container: HTTPS smoke"
"${PODMAN[@]}" exec work_container sh -c '
for u in https://google.com https://www.salesforce.com https://vrpinc.my.site.com/; do
  curl -4 -o /dev/null -s -w "%{url_effective} code=%{http_code} time=%{time_total}s\n" --max-time 25 "$u" || echo "FAIL: $u"
done
'

section "Container: TLS"
"${PODMAN[@]}" exec work_container sh -c '
for h in www.salesforce.com vrpinc.my.site.com; do
  echo "--- ${h} ---"
  timeout 20 openssl s_client -connect "${h}:443" -servername "$h" </dev/null 2>&1 | tail -3
done
'
