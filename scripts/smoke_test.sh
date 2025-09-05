#!/usr/bin/env bash
set -euo pipefail

COMMUNITY="${SNMP_ROCOMMUNITY:-public}"

hr(){ printf "\n%s\n" "============================================================"; }
shorth(){ printf "\n--- %s ---\n" "$*"; }

NODES=(r1 r2)
for C in "${NODES[@]}"; do
  hr; echo "[ ${C} ] basic info"
  docker exec -u root -it "$C" bash -lc 'ip -br addr show || true'
  shorth "vtysh: show ip bgp summary"
  docker exec -u root -it "$C" vtysh -c 'show ip bgp summary' || true
  shorth "vtysh: show ip route bgp"
  docker exec -u root -it "$C" vtysh -c 'show ip route bgp' || true
done

hr; echo "[ Data-plane ping ] hosts ↔ SVIs"
shorth "h10 -> R1 SVI (10.0.10.1)"
docker exec -it h10 ping -c3 10.0.10.1 || true
shorth "h20 -> R2 SVI (10.0.20.1)"
docker exec -it h20 ping -c3 10.0.20.1 || true

hr; echo "[ Cross-VLAN ping ] via R1<->R2 eBGP"
shorth "h10 -> h20 (10.0.20.100)"
docker exec -it h10 ping -c3 10.0.20.100 || true
shorth "h20 -> h10 (10.0.10.100)"
docker exec -it h20 ping -c3 10.0.10.100 || true

hr; echo "[ SNMP over mgmtnet ] l2a/l2b sysDescr"
docker exec -it r1 snmpwalk -v2c -c "${COMMUNITY}" 192.168.0.11:161 1.3.6.1.2.1.1.1.0 || true
docker exec -it r1 snmpwalk -v2c -c "${COMMUNITY}" 192.168.0.12:161 1.3.6.1.2.1.1.1.0 || true

hr; echo "Done."
