#!/usr/bin/env bash
set -euo pipefail

# Quick self-diagnosis for "failed to set up container networking: Address already in use"
# Prints Compose networks, allocations, and host-side overlaps.

PROJECT_PREFIX=${PROJECT_PREFIX:-frr-snmp-lab}
NETS=("${PROJECT_PREFIX}_labnet" "${PROJECT_PREFIX}_mgmtnet" "${PROJECT_PREFIX}_vlan10" "${PROJECT_PREFIX}_vlan20")

echo "== Docker networks (grep: ${PROJECT_PREFIX}) =="
docker network ls | grep -E "${PROJECT_PREFIX}|NAME|^$" || true

for N in "${NETS[@]}"; do
  echo
  echo "== Inspect: ${N} =="
  docker network inspect "${N}" >/tmp/inspect.json 2>/dev/null || { echo "(not found)"; continue; }
  echo "IPAM.Config:"; jq '.[0].IPAM.Config' </tmp/inspect.json || true
  echo "Allocations (name: IPv4Address):"; jq -r '.[0].Containers | to_entries[] | "\(.value.Name): \(.value.IPv4Address)"' </tmp/inspect.json || true
done

echo
echo "== Host routing table (IPv4) matches for common lab subnets =="
ROUTES_RE='(10\.77\.|172\.23\.)'
netstat -rn -f inet 2>/dev/null | awk "/$ROUTES_RE/ || NR==1" || true

echo
echo "== Host interfaces (IPv4) summary =="
ifconfig | awk '/flags=/{iface=$1} /inet /{print iface, $2}' || true

echo
echo "== Containers status =="
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}' | sed -n '1,200p'

echo
echo "Hint: if a fixed IP (e.g., .1 or .2) is listed twice in a network, remove that network and recreate:"
echo "  docker network rm ${NETS[*]} || true"
echo "  docker compose -f docker-compose.yml -f docker-compose.dual-plane.yml -f docker-compose.l2-access.yml up -d --build"

