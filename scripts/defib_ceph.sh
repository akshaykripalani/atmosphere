#!/usr/bin/env bash

# Defibrillate Ceph services after a reboot.
# - Starts the local Ceph MON systemd unit (if present)
# - Verifies cluster status via cephadm
# - Retrieves the cephadm public key (mgr-backed)
#
# Defaults (override via environment):
#   FSID=<auto-detected from /var/lib/ceph>
#   HOST=$(hostname -s)

set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

detect_fsid() {
  # Pick the first directory under /var/lib/ceph matching UUIDv4
  local found
  found=$(ls -1 /var/lib/ceph 2>/dev/null | grep -E '^[0-9a-f-]{36}$' | head -n1 || true)
  if [[ -z "${found}" ]]; then
    echo ""; return 0
  fi
  echo "${found}"
}

FSID=${FSID:-$(detect_fsid)}
HOST=${HOST:-$(hostname -s)}

if [[ -z "${FSID}" ]]; then
  echo "Could not auto-detect Ceph FSID under /var/lib/ceph." >&2
  exit 1
fi

MON_UNIT="ceph-${FSID}@mon.${HOST}.service"

echo "[defib_ceph] Attempting to start MON unit: ${MON_UNIT}"
if systemctl list-unit-files | grep -q "${MON_UNIT}"; then
  systemctl start "${MON_UNIT}" || true
else
  # Try to start even if not listed (unit may be transient)
  systemctl start "${MON_UNIT}" || true
fi

echo "[defib_ceph] Checking Ceph cluster status..."
if ! cephadm shell -- ceph -s; then
  echo "[defib_ceph] WARN: ceph -s failed. Ensure networking (br-mgmt) is restored and MON is reachable." >&2
  exit 2
fi

echo "[defib_ceph] Retrieving cephadm public key..."
cephadm shell -- ceph cephadm get-pub-key

echo "[defib_ceph] Done."


