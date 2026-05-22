#!/usr/bin/env bash
# Quick VPN egress checks inside work_container (requires sudo podman).
set -euo pipefail

PODMAN=(sudo podman)

if ! "${PODMAN[@]}" ps --format '{{.Names}}' | grep -qx work_container; then
  echo "work_container is not running." >&2
  exit 1
fi

echo "=== VPN / DNS ==="
"${PODMAN[@]}" exec work_container cat /etc/resolv.conf
"${PODMAN[@]}" exec work_container sh -c 'swanctl --list-sas 2>/dev/null | head -12'
echo "ipv6 disabled: $("${PODMAN[@]}" exec work_container cat /proc/sys/net/ipv6/conf/all/disable_ipv6)"

echo
echo "=== HTTPS (curl -4, TCP/TLS) ==="
"${PODMAN[@]}" exec work_container sh -c '
for u in https://google.com https://www.salesforce.com https://vrpinc.my.site.com/; do
  curl -4 -o /dev/null -s -w "%{url_effective} code=%{http_code} time=%{time_total}s\n" --max-time 30 "$u" || echo "FAIL: $u"
done
'

echo
echo "=== TLS handshake (openssl) ==="
"${PODMAN[@]}" exec work_container sh -c '
for h in www.salesforce.com vrpinc.my.site.com; do
  echo "--- ${h} ---"
  timeout 20 openssl s_client -connect "${h}:443" -servername "$h" </dev/null 2>&1 | tail -5
done
'
