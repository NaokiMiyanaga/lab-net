\
  #!/usr/bin/env bash
  set -euo pipefail
  source /init/_common.sh

  start_snmpd
  start_frr_daemons
  wait_for_vty

  # Discover r2's container IP via DNS in the default compose network
  PEER_IP="$(getent hosts r2 | awk '{print $1}')"
  configure_min_policy "${PEER_IP}" "65001"

  # Leave BGP `network` statements to the user (see README).
  # tail logs in foreground to keep container attached
  tail -f /init/start.log
