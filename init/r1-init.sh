#!/usr/bin/env bash
set -euo pipefail
source /init/_common.sh

prepare_ansible_tmp

start_snmpd
start_frr_daemons
wait_for_vty

# Determine BGP params (env overrides, with sensible defaults)
MY_ASN="${MY_ASN:-65001}"
PEER_ASN="${PEER_ASN:-65002}"
if [[ -n "${PEER_IP:-}" ]]; then
  : # use provided PEER_IP
else
  # Discover r2's container IP via DNS in the default compose network
  PEER_IP="$(getent hosts r2 | awk '{print $1}')"
fi
configure_min_policy "${PEER_IP}" "${MY_ASN}" "${PEER_ASN}"

# Optionally advertise prefixes
advertise_prefixes "${MY_ASN}"

# Leave BGP `network` statements to the user (see README).
# tail logs in foreground to keep container attached
tail -f /init/start.log
