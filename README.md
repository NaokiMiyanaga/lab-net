\
  # FRR + SNMP (AgentX) Mini Lab

  [日本語 README](README.ja.md)

  A minimal two-router lab running FRRouting (zebra/bgpd) with the SNMP modules,
  fronted by Net-SNMP as an AgentX master. Verified on macOS with OrbStack (Docker Desktop should also work).


  ## What’s inside

  - `docker-compose.yml` — base services for r1/r2
  - `docker-compose.dual-plane.yml` — separates service-plane(labnet) and mgmt-plane(mgmtnet)
  - `docker-compose.l2-access.yml` — L2 access segments (vlan10/20), hosts h10/h20
  - `Dockerfile` — installs `frr`, `frr-snmp`, `snmpd` and utilities
  - `init/_common.sh`, `init/r1-init.sh`, `init/r2-init.sh`, `init/l2-init.sh`
  - `scripts/lab.sh` — one-liner wrapper (up/down/smoke/diag)
  - `scripts/show_frr_status.sh`, `scripts/smoke_test.sh`, `scripts/diag_net_conflicts.sh`

  ## Requirements

  - Docker engine. On macOS we tested with **OrbStack** (recommended for performance) and it worked the same with Docker networking semantics.
  - `snmpwalk` present on the host if you want to query from the host (Net-SNMP CLI).

  ### Optional: OrbStack notes (macOS)

  - Installing OrbStack gives you Docker + Linux VM. Removing OrbStack removes that Docker stack.
  - If you uninstall OrbStack and install Docker Desktop instead, this lab should still work unchanged.

  ## Quick start

  ```bash
  # Recommended profile: dual-plane + L2 access
  bash scripts/lab.sh up
  bash scripts/lab.sh smoke   # interfaces, BGP, dataplane, SNMP
  bash scripts/lab.sh diag    # diagnose host-side network conflicts
  bash scripts/lab.sh down    # tear down
  ```

  Addresses (defaults):
  - mgmtnet 192.168.0.0/24 — r1=192.168.0.1, r2=192.168.0.2, l2a=.11, l2b=.12
  - labnet  10.0.0.0/24 — r1=10.0.0.1, r2=10.0.0.2 (eBGP)
  - vlan10  10.0.10.0/24 — r1 SVI=10.0.10.1, h10=10.0.10.100 (l2a has 10.0.10.2)
  - vlan20  10.0.20.0/24 — r2 SVI=10.0.20.1, h20=10.0.20.100 (l2b has 10.0.20.2)

  ### Other overlays (profiles)

  - L3 switch style (SVIs on separate L2 segments)
    - Overlay: `docker-compose.l3sw.yml`
    - Segments: `lan10`=10.0.10.0/24, `lan20`=10.0.20.0/24, transit=198.51.100.0/24
    - Usage: `docker compose -f docker-compose.yml -f docker-compose.l3sw.yml up -d --build`

  - Common 4-node profile (L3×2 + L2×2)
    - Overlay: `docker-compose.common-4node.yml`
    - Mgmt: 192.168.0.0/24 (r1=192.168.0.1, r2=192.168.0.2)
    - Transit eBGP: 10.0.0.0/30 (r1 .2, r2 .3)
    - Service L2: `lan10`=10.0.10.0/24 (r1 SVI .1), `lan20`=10.0.20.0/24 (r2 SVI .1)
    - Usage: `docker compose -f docker-compose.yml -f docker-compose.common-4node.yml up -d --build`

  ### BGP (auto-config)

  The combined overlays auto-configure eBGP neighbors and permissive route-maps:
  - r1 (AS 65001): neighbor 10.0.0.2 (AS 65002), advertises 10.0.10.0/24
  - r2 (AS 65002): neighbor 10.0.0.1 (AS 65001), advertises 10.0.20.0/24

  Notes for L2 access model
  - Docker bridge does not carry 802.1Q tags. VLANs are modeled as separate bridges (`vlan10`, `vlan20`).
  - There is no L2 link between L2A and L2B; each VLAN is independent.
  - Gateways are set to `.254` so `.1` can be used by SVIs.
  - In dual-plane, SNMP exposure to host is disabled (`ports: []`). Use a management-net container to query.

  ### Verify BGP

  ```bash
  docker exec -it r1 vtysh -c 'show ip bgp summary'
  docker exec -it r2 vtysh -c 'show ip bgp summary'

  docker exec -it r1 vtysh -c 'show ip route bgp'   # expect 10.0.2.0/24 via r2
  docker exec -it r2 vtysh -c 'show ip route bgp'   # expect 10.0.1.0/24 via r1
  ```

  ### Query via SNMP (host)

  ```bash
  # BGP4-MIB peer table (host -> r1)
  snmpwalk -v2c -c public 127.0.0.1:10161 1.3.6.1.2.1.15.3.1 | head

  # BGP4-MIB peer table (host -> r2)
  snmpwalk -v2c -c public 127.0.0.1:20161 1.3.6.1.2.1.15.3.1 | head
  ```

  ### Query inside the container

  ```bash
  docker exec -it r1 snmpwalk -v2c -c public 127.0.0.1:161 1.3.6.1.2.1.15.3.1 | head
  ```

  ## Policy (single source of truth)

  - `policy/master.ietf.yaml` holds the network design in RFC8345-like form with `operational:*` extensions for Compose/BGP/VLAN/SNMP.
  - Compose overlays and diagrams are kept in sync with this file.

  ## IETF-style YAML (validation)

  - Topology (dual-plane): `ietf/topology.dual-plane.yaml`
  - Device interfaces (examples): `ietf/r1-interfaces.yaml`, `ietf/r2-interfaces.yaml`
  - JSON versions are included for strict tooling: `ietf/topology.dual-plane.json`, `ietf/r1-interfaces.json`, `ietf/r2-interfaces.json`
  - Validation/ETL (with an external repo providing the schema):
    ```bash
    # example layout
    #   ../ietf-network-schema/    (schema + tools)
    #   ./                        (this repo)
    SCHEMA_REPO=../ietf-network-schema
    python3 "$SCHEMA_REPO/scripts/validate.py" \
      --schema "$SCHEMA_REPO/schema/schema.json" \
      --data ietf/topology.dual-plane.yaml
    ```

  ## Maintenance / Troubleshooting

  - View logs inside a router: `docker logs r1` (look for `/init/start.log` tail)
  - Check AgentX socket: `docker exec -it r1 ss -xap | grep /var/agentx/master`
  - If BGP shows `(Policy)`, ensure the route-maps exist and are attached (the init scripts do this).

  ## Port mapping (host → container)

  | Host UDP | Container | Purpose |
  |---:|:---:|:---|
  | 10161 | r1:161/udp | SNMP to r1 |
  | 20161 | r2:161/udp | SNMP to r2 |

  ## Topology (ASCII)

  ```text
  +----------------------+        docker bridge (subnet varies per run)        +----------------------+
  |        R1            |<------------------- 172.19.0.0/16 ----------------->|         R2           |
  |  hostname: r1        |                                                     |   hostname: r2       |
  |  AS: 65001           |  eth0: 172.19.0.3/16  ——  peer ——  eth0: 172.19.0.2/16  |   AS: 65002        |
  |  SNMP: UDP 10161<-161|                                                     |  SNMP: UDP 20161<-161|
  |  bgpd + zebra + SNMP |                                                     |  bgpd + zebra + SNMP |
  +----------------------+                                                     +----------------------+
  ```

  See `topology.ascii.txt` for the dual-plane + L2 access model used in this repo
  (mgmtnet=192.168.0.0/24, labnet=10.0.0.0/24, vlan10/20 segments; no L2 trunk).

  ## License

  MIT
