#!/usr/bin/env bash
set -euo pipefail
source /init/_common.sh

prepare_ansible_tmp

echo "[l2-init] starting SNMPD for L2SW placeholder..."
start_snmpd
echo "[l2-init] SNMP ready (community=${SNMP_ROCOMMUNITY:-public})"

# No local bridging when backend=docker-bridge; VLANs are modeled via Docker networks.
# Keep the container alive and stream logs to stdout.
tail -f /init/start.log
