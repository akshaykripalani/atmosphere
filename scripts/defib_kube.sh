#!/usr/bin/env bash

# Defibrillate AIO networking after a reboot.
# - Recreates management bridge (br-mgmt) with a dummy member and host IP
# - Recreates external bridge (br-ex) with host IP
# - Reinstates NAT for the external subnet
#
# Defaults (override via environment):
#   MGMT_BR=br-mgmt
#   MGMT_IP_CIDR=10.96.240.200/24
#   EX_BR=br-ex
#   EX_IP_CIDR=10.96.250.10/24
#   EX_SUBNET_CIDR=10.96.250.0/24

set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

MGMT_BR=${MGMT_BR:-br-mgmt}
MGMT_IP_CIDR=${MGMT_IP_CIDR:-10.96.240.200/24}

EX_BR=${EX_BR:-br-ex}
EX_IP_CIDR=${EX_IP_CIDR:-10.96.250.10/24}
EX_SUBNET_CIDR=${EX_SUBNET_CIDR:-10.96.250.0/24}

DEFAULT_DEV=$(ip route show default | awk '/default/ {print $5; exit}')
if [[ -z "${DEFAULT_DEV}" ]]; then
  echo "Could not determine default network interface." >&2
  exit 1
fi

ensure_bridge() {
  local br_name=$1
  if ! ip link show "${br_name}" >/dev/null 2>&1; then
    ip link add name "${br_name}" type bridge
  fi
}

ensure_dummy() {
  # Create a dummy interface if not present; attach to the specified bridge
  local br_name=$1
  if ! ip link show dummy0 >/dev/null 2>&1; then
    ip link add dummy0 type dummy
  fi
  # Attach dummy0 to the bridge (idempotent)
  ip link set dummy0 master "${br_name}" 2>/dev/null || true
  ip link set dummy0 up || true
}

ensure_ip_on_iface() {
  local iface=$1
  local ip_cidr=$2
  if ! ip -4 addr show dev "${iface}" | grep -qw "${ip_cidr}"; then
    ip addr add "${ip_cidr}" dev "${iface}"
  fi
}

ensure_iface_up() {
  local iface=$1
  ip link set "${iface}" up
}

ensure_nat_rule() {
  local src_cidr=$1
  local out_dev=$2
  if ! iptables -t nat -C POSTROUTING -s "${src_cidr}" -o "${out_dev}" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s "${src_cidr}" -o "${out_dev}" -j MASQUERADE
  fi
}

echo "[defib_kube] Restoring management bridge ${MGMT_BR}..."
ensure_bridge "${MGMT_BR}"
ensure_dummy "${MGMT_BR}"
ensure_ip_on_iface "${MGMT_BR}" "${MGMT_IP_CIDR}"
ensure_iface_up "${MGMT_BR}"

echo "[defib_kube] Restoring external bridge ${EX_BR}..."
ensure_bridge "${EX_BR}"
ensure_ip_on_iface "${EX_BR}" "${EX_IP_CIDR}"
ensure_iface_up "${EX_BR}"

echo "[defib_kube] Ensuring NAT from ${EX_SUBNET_CIDR} via ${DEFAULT_DEV}..."
ensure_nat_rule "${EX_SUBNET_CIDR}" "${DEFAULT_DEV}"

echo "[defib_kube] Done. Summary:"
echo "  - ${MGMT_BR}: $(ip -br addr show ${MGMT_BR} | awk '{print $3, $4, $5}')"
echo "  - ${EX_BR}:   $(ip -br addr show ${EX_BR}   | awk '{print $3, $4, $5}')"
echo "  - NAT:        POSTROUTING -s ${EX_SUBNET_CIDR} -o ${DEFAULT_DEV} MASQUERADE (present)"


