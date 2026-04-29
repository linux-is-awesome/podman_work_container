#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${WORK_CONTAINER_CONFIG_DIR:-/config}"
VPN_ENV_FILE="${WORK_CONTAINER_VPN_ENV_FILE:-${CONFIG_DIR}/vpn.env}"
VPN_TEMPLATE_FILE="${WORK_CONTAINER_SWANCTL_TEMPLATE:-${CONFIG_DIR}/swanctl.conf.template}"

if [[ -f "${VPN_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${VPN_ENV_FILE}"
fi

: "${VPN_CONN:=vrp}"
: "${VPN_CHILD:=vrp-child}"
: "${VPN_SERVER:?Set VPN_SERVER in ${VPN_ENV_FILE}}"
: "${VPN_REMOTE_ID:?Set VPN_REMOTE_ID in ${VPN_ENV_FILE}}"
: "${VPN_USERNAME:?Set VPN_USERNAME in ${VPN_ENV_FILE}}"
: "${VPN_PASSWORD:?Set VPN_PASSWORD in ${VPN_ENV_FILE}}"
: "${VPN_LOCAL_ID:=%any}"
: "${VPN_IKE_PROPOSAL:=aes256-sha256-modp2048}"
: "${VPN_ESP_PROPOSAL:=aes256-sha256-modp2048}"
: "${VPN_SERVER_ADDR:=}"

if [[ ! -f "${VPN_TEMPLATE_FILE}" ]]; then
  echo "Missing template: ${VPN_TEMPLATE_FILE}" >&2
  exit 1
fi

IPSEC_BIN="$(command -v ipsec)"
SWANCTL_BIN="$(command -v swanctl)"

DEFAULT_IFACE="$(ip route show default | awk '/default/ {print $5; exit}')"
if [[ -z "${DEFAULT_IFACE}" ]]; then
  echo "Could not detect default network interface" >&2
  exit 1
fi

VPN_SERVER_IP="$(getent ahostsv4 "${VPN_SERVER}" | awk '{print $1; exit}')"
if [[ -z "${VPN_SERVER_IP}" ]]; then
  echo "Could not resolve VPN_SERVER=${VPN_SERVER}" >&2
  exit 1
fi
if [[ -z "${VPN_SERVER_ADDR}" ]]; then
  VPN_SERVER_ADDR="${VPN_SERVER_IP}"
fi

mkdir -p /etc/swanctl
# envsubst only reads exported environment variables.
export VPN_CONN VPN_CHILD VPN_SERVER VPN_SERVER_ADDR VPN_REMOTE_ID VPN_USERNAME VPN_PASSWORD VPN_LOCAL_ID VPN_IKE_PROPOSAL VPN_ESP_PROPOSAL
envsubst < "${VPN_TEMPLATE_FILE}" > /etc/swanctl/swanctl.conf

# Make system CAs available to swanctl/charon certificate validation.
mkdir -p /etc/swanctl/x509ca
if compgen -G "/etc/ssl/certs/*.pem" >/dev/null; then
  cp -f /etc/ssl/certs/*.pem /etc/swanctl/x509ca/ 2>/dev/null || true
fi

echo "[work_container] Applying kill-switch firewall rules..."
iptables -F
iptables -t nat -F
iptables -X
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Baseline: loopback + established traffic.
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Only allow IKE/NAT-T to VPN gateway before tunnel is up.
iptables -A OUTPUT -o "${DEFAULT_IFACE}" -d "${VPN_SERVER_IP}" -p udp --dport 500 -j ACCEPT
iptables -A OUTPUT -o "${DEFAULT_IFACE}" -d "${VPN_SERVER_IP}" -p udp --dport 4500 -j ACCEPT

echo "[work_container] Starting strongSwan..."
"${IPSEC_BIN}" start
sleep 1

echo "[work_container] Loading and initiating ${VPN_CONN}..."
"${SWANCTL_BIN}" --load-all
"${SWANCTL_BIN}" --initiate --child "${VPN_CHILD}"

# Wait for tunnel.
for _ in $(seq 1 20); do
  if "${SWANCTL_BIN}" --list-sas | grep -q "${VPN_CONN}"; then
    break
  fi
  sleep 1
done

if ! "${SWANCTL_BIN}" --list-sas | grep -q "${VPN_CONN}"; then
  echo "[work_container] VPN did not come up; keeping egress blocked." >&2
  exit 1
fi

# Keep only VPN-protected traffic plus VPN maintenance packets.
iptables -A OUTPUT -m policy --pol ipsec --dir out -j ACCEPT
iptables -A INPUT -m policy --pol ipsec --dir in -j ACCEPT
iptables -A OUTPUT -o "${DEFAULT_IFACE}" -d "${VPN_SERVER_IP}" -p udp --dport 500 -j ACCEPT
iptables -A OUTPUT -o "${DEFAULT_IFACE}" -d "${VPN_SERVER_IP}" -p udp --dport 4500 -j ACCEPT

PUBLIC_IP="$(curl -4 --max-time 10 -fsSL ifconfig.me 2>/dev/null || true)"
if [[ -n "${PUBLIC_IP}" ]]; then
  echo "[work_container] Public egress IP: ${PUBLIC_IP}"
else
  echo "[work_container] Public egress IP: unavailable"
fi

echo "[work_container] VPN is up. Starting command: $*"
exec "$@"
