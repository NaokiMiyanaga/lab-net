\
  #!/usr/bin/env bash
  set -euo pipefail
  exec > >(tee -a /init/start.log) 2>&1

  # Pick FRR modules directory by arch/distro
  detect_modules_dir() {
    if [ -d /usr/lib/aarch64-linux-gnu/frr/modules ]; then
      echo /usr/lib/aarch64-linux-gnu/frr/modules
    elif [ -d /usr/lib/x86_64-linux-gnu/frr/modules ]; then
      echo /usr/lib/x86_64-linux-gnu/frr/modules
    elif [ -d /usr/lib/frr/modules ]; then
      echo /usr/lib/frr/modules
    else
      # Fallback; zebra/bgpd will still run without modules dir override,
      # but SNMP modules will fail. We log and continue.
      echo ""
    fi
  }

  start_snmpd() {
    mkdir -p /var/agentx /var/run/agentx
    ln -sfn /var/agentx /var/run/agentx
    chown -R Debian-snmp:Debian-snmp /var/agentx || true
    chmod 0777 /var/agentx || true

    cp /init/common-snmpd.conf /etc/snmp/snmpd.conf
    pkill -x snmpd || true
    # Foreground & log to stdout (container)
    snmpd -C -c /etc/snmp/snmpd.conf -f -Lo &
    # Give it a moment to create the AgentX socket
    sleep 1
  }

  start_frr_daemons() {
    export NETSNMP_AGENTX_SOCKET=/var/agentx/master
    local MODDIR="$(detect_modules_dir)"
    local MODOPT=()
    if [ -n "$MODDIR" ]; then MODOPT=(--moduledir "$MODDIR"); fi

    # Clean old pid files if any
    rm -f /var/run/frr/*.pid || true

    # Start zebra/bgpd with SNMP modules
    /usr/lib/frr/zebra "${MODOPT[@]}" -d -A 127.0.0.1 -M zebra_snmp
    /usr/lib/frr/bgpd  "${MODOPT[@]}" -d -A 127.0.0.1 -M bgpd_snmp
  }

  wait_for_vty() {
    for i in $(seq 1 30); do
      if vtysh -c 'show version' >/dev/null 2>&1; then return 0; fi
      sleep 1
    done
    echo "WARN: vtysh not ready after 30s; continuing" >&2
    return 0
  }

  # Minimal permissive route-maps to satisfy ebgp-requires-policy
  configure_min_policy() {
    local PEER_IP="$1"
    local MY_ASN="$2"
    vtysh -c 'conf t' \
      -c "router bgp ${MY_ASN}" \
      -c "neighbor ${PEER_IP} remote-as $([ "${MY_ASN}" = "65001" ] && echo 65002 || echo 65001)" \
      -c 'exit' \
      -c 'route-map RM-OUT permit 10' \
      -c 'exit' \
      -c "router bgp ${MY_ASN}" \
      -c "neighbor ${PEER_IP} route-map RM-OUT out" \
      -c 'exit' \
      -c 'route-map RM-IN permit 10' \
      -c 'exit' \
      -c "router bgp ${MY_ASN}" \
      -c "neighbor ${PEER_IP} route-map RM-IN in" \
      -c 'end' || true
  }
