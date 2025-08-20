\
  # FRR + SNMP (AgentX) Mini Lab

  A minimal two-router lab running FRRouting (zebra/bgpd) with the SNMP modules,
  fronted by Net-SNMP as an AgentX master. Verified on macOS with OrbStack (Docker Desktop should also work).

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

  > IP addresses above reflect a typical run (compose default network in our tests).
  > If your bridge range differs, check with `docker exec r1 ip -br a`.

  ## What’s inside

  - `docker-compose.yml` — spins up **r1** and **r2** (Debian bookworm), exposes SNMP/UDP on host
  - `Dockerfile` — installs `frr`, `frr-snmp`, `snmpd` and basic utils
  - `init/common-snmpd.conf` — Net-SNMP master AgentX config
  - `init/_common.sh` — shared helpers
  - `init/r1-init.sh`, `init/r2-init.sh` — start SNMPD, start `zebra/bgpd` with SNMP modules, pre-wire permissive route-maps (no networks advertised by default)
  - `scripts/show_frr_status.sh` — one-shot status (BGP + BGP4-MIB via SNMP)

  ## Requirements

  - Docker engine. On macOS we tested with **OrbStack** (recommended for performance) and it worked the same with Docker networking semantics.
  - `snmpwalk` present on the host if you want to query from the host (Net-SNMP CLI).

  ### Optional: OrbStack notes (macOS)

  - Installing OrbStack gives you Docker + Linux VM. Removing OrbStack removes that Docker stack.
  - If you uninstall OrbStack and install Docker Desktop instead, this lab should still work unchanged.

  ## Quick start

  ```bash
  docker compose up -d --build
  # Check
  bash scripts/show_frr_status.sh
  ```

  At this point sessions are up but **no prefixes** are advertised yet (empty RIB).  
  The init scripts created both **RM-OUT** and **RM-IN** route-maps and attached them, so you can start advertising safely.

  ### Advertise one prefix on each router

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

  > If you want to ensure reachability in the local RIB, you can also add a blackhole route inside each container:
  > `ip route add 10.0.1.0/24 dev lo` on r1 and `ip route add 10.0.2.0/24 dev lo` on r2.

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

  ## Maintenance / Troubleshooting

  - View logs inside a router: `docker logs r1` (look for `/init/start.log` tail)
  - Check AgentX socket: `docker exec -it r1 ss -xap | grep /var/agentx/master`
  - If BGP shows `(Policy)`, ensure the route-maps exist and are attached (the init scripts do this).

  ## Port mapping (host → container)

  | Host UDP | Container | Purpose |
  |---:|:---:|:---|
  | 10161 | r1:161/udp | SNMP to r1 |
  | 20161 | r2:161/udp | SNMP to r2 |

  ## License

  MIT
