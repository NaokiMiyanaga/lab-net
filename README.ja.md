\
  # FRR + SNMP (AgentX) ミニラボ

  FRRouting（zebra/bgpd）を Net-SNMP（AgentX マスター）でフロントし、BGP4-MIB を引ける最小構成の 2 ルータ環境です。
  macOS（OrbStack で検証）/ Docker で動作します。

  ## トポロジ（ASCII）

  ```text
  +----------------------+        docker bridge（実行ごとに変動あり）         +----------------------+
  |        R1            |<------------------ 172.19.0.0/16 ------------------>|         R2           |
  |  hostname: r1        |                                                      |   hostname: r2       |
  |  AS: 65001           |  eth0: 172.19.0.3/16  ——  peer ——  eth0: 172.19.0.2/16  |   AS: 65002        |
  |  SNMP: UDP 10161<-161|                                                      |  SNMP: UDP 20161<-161|
  |  bgpd + zebra + SNMP |                                                      |  bgpd + zebra + SNMP |
  +----------------------+                                                      +----------------------+
  ```

  > 上記 IP は一例です。実際のサブネットは `docker exec r1 ip -br a` などで確認してください。

  ## 構成物

  - `docker-compose.yml` — **r1 / r2** を起動。ホストの UDP 10161/20161 を公開
  - `Dockerfile` — `frr`, `frr-snmp`, `snmpd` を導入
  - `init/common-snmpd.conf` — Net-SNMP の AgentX 設定
  - `init/_common.sh` — 共通ヘルパ
  - `init/r1-init.sh`, `init/r2-init.sh` — SNMPD と `zebra/bgpd` を SNMP モジュール付きで起動。`RM-IN/OUT` の空ルートマップを作成（広告は未設定）
  - `scripts/show_frr_status.sh` — まとめて BGP / SNMP(BGP4-MIB) を確認

  ## 事前準備

  - Docker が必要です。macOS では **OrbStack** で検証しました（Docker Desktop でも動作します）。
  - ホストで `snmpwalk`（Net-SNMP CLI）を使う場合は導入してください。

  ### OrbStack（macOS）の補足

  - OrbStack は Docker+Linux VM を提供します。アンインストールするとその Docker も消えます。
  - Docker Desktop に入れ替えても、本ラボはそのまま動きます。

  ## 使い方（Quick start）

  ```bash
  docker compose up -d --build
  bash scripts/show_frr_status.sh   # 起動確認
  ```

  初期状態では BGP セッションは Up ですが、**経路広告はありません**。  
  既に `RM-OUT` / `RM-IN` は適用済みなので、ネットワークを追加すれば広告できます。

  ### それぞれ 1 プレフィックスを広告

  ```bash
  # R1: 10.0.1.0/24 を広告
  docker exec -it r1 vtysh -c 'conf t' \
    -c 'router bgp 65001' \
    -c 'network 10.0.1.0/24' \
    -c 'end'

  # R2: 10.0.2.0/24 を広告
  docker exec -it r2 vtysh -c 'conf t' \
    -c 'router bgp 65002' \
    -c 'network 10.0.2.0/24' \
    -c 'end'
  ```

  > RIB に経路を作るため、必要なら各コンテナでブラックホールルートを追加してください：  
  > R1: `ip route add 10.0.1.0/24 dev lo` / R2: `ip route add 10.0.2.0/24 dev lo`

  ### BGP の確認

  ```bash
  docker exec -it r1 vtysh -c 'show ip bgp summary'
  docker exec -it r2 vtysh -c 'show ip bgp summary'

  docker exec -it r1 vtysh -c 'show ip route bgp'   # R2の 10.0.2.0/24 が入る
  docker exec -it r2 vtysh -c 'show ip route bgp'   # R1の 10.0.1.0/24 が入る
  ```

  ### SNMP での確認（ホストから）

  ```bash
  # r1 の BGP4-MIB peer table
  snmpwalk -v2c -c public 127.0.0.1:10161 1.3.6.1.2.1.15.3.1 | head
  # r2
  snmpwalk -v2c -c public 127.0.0.1:20161 1.3.6.1.2.1.15.3.1 | head
  ```

  ### コンテナ内からの確認

  ```bash
  docker exec -it r1 snmpwalk -v2c -c public 127.0.0.1:161 1.3.6.1.2.1.15.3.1 | head
  ```

  ## メンテ / トラブルシュート

  - コンテナログ: `docker logs r1`（`/init/start.log` が継続表示されます）
  - AgentX ソケット: `docker exec -it r1 ss -xap | grep /var/agentx/master`
  - BGP が `(Policy)` の場合はルートマップが適用されているか確認（本 init で自動適用済み）

  ## ポートマッピング（ホスト → コンテナ）

  | ホスト UDP | コンテナ | 用途 |
  |---:|:---:|:---|
  | 10161 | r1:161/udp | r1 へ SNMP |
  | 20161 | r2:161/udp | r2 へ SNMP |

  ## ライセンス

  MIT
