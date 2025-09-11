# Usage Guide (English)

Detailed usage for the FRR + Linux Bridge + SNMP/AgentX validation network.

## Recommended profile (dual-plane + L2 access)

- mgmt plane: mgmtnet=192.168.0.0/24 (r1=.1, r2=.2, l2a=.11, l2b=.12)
- service plane: labnet=10.0.0.0/24 (r1=.1, r2=.2)
- data plane: vlan10=10.0.10.0/24 (R1 SVI .1, h10 .100) / vlan20=10.0.20.0/24 (R2 SVI .1, h20 .100)

Start with `bash scripts/lab.sh up` (internally composes dual-plane + L2 access).

## Advertise one prefix on each router

```bash
# R1: advertise 10.0.1.0/24
docker exec -it r1 vtysh -c 'conf t' \
  -c 'router bgp 65001' \
  -c 'network 10.0.1.0/24' \
  -c 'end'

# R2: advertise 10.0.2.0/24
docker exec -it r2 vtysh -c 'conf t' \
  -c 'router bgp 65002' \
  -c 'network 10.0.2.0/24' \
  -c 'end'
```

Note: add a blackhole route if needed (e.g., `ip route add 10.0.1.0/24 dev lo`).

## Verify BGP

```bash
docker exec -it r1 vtysh -c 'show ip bgp summary'
docker exec -it r2 vtysh -c 'show ip bgp summary'

docker exec -it r1 vtysh -c 'show ip route bgp'
docker exec -it r2 vtysh -c 'show ip route bgp'
```

## Verify via SNMP

When exposed on host (single-net profile):

```bash
snmpwalk -v2c -c public 127.0.0.1:10161 1.3.6.1.2.1.15.3.1 | head   # r1
snmpwalk -v2c -c public 127.0.0.1:20161 1.3.6.1.2.1.15.3.1 | head   # r2
```

Inside container:

```bash
docker exec -it r1 snmpwalk -v2c -c public 127.0.0.1:161 1.3.6.1.2.1.15.3.1 | head
```

In dual-plane, host exposure is disabled (`ports: []`). Query from a mgmt-net container instead.

## Customization (env vars)

- `MY_ASN` / `PEER_ASN`, `PEER_IP`, `ADVERTISE_PREFIXES`
- `SNMP_ROCOMMUNITY` (default `public`), `BGP_ROUTER_ID`, `BGP_UPDATE_SOURCE`

Compose example (excerpt):

```yaml
services:
  r1:
    environment:
      - MY_ASN=65001
      - PEER_ASN=65002
      - SNMP_ROCOMMUNITY=public
  r2:
    environment:
      - MY_ASN=65002
      - PEER_ASN=65001
      - SNMP_ROCOMMUNITY=public
```

## Other profiles

- L3 switch style (SVIs on separate L2 segments)

```bash
docker compose -f docker-compose.yml -f docker-compose.l3sw.yml up -d --build
```

- Common 4-node (L3×2 + L2×2)

```bash
docker compose -f docker-compose.yml -f docker-compose.common-4node.yml up -d --build
```

## L2 access only

```bash
docker compose -f docker-compose.yml -f docker-compose.dual-plane.yml -f docker-compose.l2-access.yml up -d --build
```

Notes:
- Docker bridge does not carry 802.1Q tags (VLANs approximated as separate networks)
- No L2 link between L2A and L2B (each VLAN is independent)
- Reserve `.254` for GW; use `.1` for router SVIs

