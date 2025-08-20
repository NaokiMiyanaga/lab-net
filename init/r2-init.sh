\
  #!/usr/bin/env bash
  set -euo pipefail
  source /init/_common.sh

  start_snmpd
  start_frr_daemons
  wait_for_vty

  # Discover r1's container IP via DNS in the default compose network
  PEER_IP="$(getent hosts r1 | awk '{print $1}')"
  configure_min_policy "${PEER_IP}" "65002"

  tail -f /init/start.log
