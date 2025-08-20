\
  #!/usr/bin/env bash
  set -euo pipefail

  NODES=(r1 r2)

  hr(){ printf '\n%s\n' "============================================================"; }
  shorth(){ printf '\n--- %s ---\n' "$*"; }

  for C in "${NODES[@]}"; do
    hr
    echo "[ ${C} ] basic info"
    docker exec -u root -it "$C" bash -lc 'uname -a; echo; ip -br addr show || true'

    shorth "vtysh: running-config (BGP section)"
    docker exec -u root -it "$C" bash -lc "
      vtysh -c 'show running-config' 2>/dev/null \
        | awk '
            /^router bgp[ ]/ {inbgp=1; print; next}
            inbgp && /^!/ {print; exit}
            inbgp {print}
          '
    " || true

    shorth "vtysh: show ip bgp summary"
    docker exec -u root -it "$C" vtysh -c 'show ip bgp summary' || true

    shorth "vtysh: show ip route bgp"
    docker exec -u root -it "$C" vtysh -c 'show ip route bgp' || true

    # SNMP (BGP4-MIB) — host-side forwarded port
    HOSTPORT="$(docker port "$C" 161/udp 2>/dev/null | sed -E 's/.*:([0-9]+)/\1/;q' || true)"
    if [[ -n "${HOSTPORT}" ]]; then
      shorth "SNMP(BGP4-MIB): via 127.0.0.1:${HOSTPORT}"
      snmpwalk -v2c -c public "127.0.0.1:${HOSTPORT}" 1.3.6.1.2.1.15.1.0 || true
      snmpwalk -v2c -c public "127.0.0.1:${HOSTPORT}" 1.3.6.1.2.1.15.3.1 | head -n 40 || true
    else
      echo "(SNMP: 161/udp not published for ${C})"
    fi
  done

  hr
  echo "Done."
