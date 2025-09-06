\
  # FRR + SNMP (AgentX) ミニラボ

  FRRouting（zebra/bgpd）を Net-SNMP（AgentX マスター）でフロントし、BGP4-MIB を引ける最小構成の 2 ルータ環境です。
  macOS（OrbStack で検証）/ Docker で動作します。

  ## 構成物

  - `docker-compose.yml` — **r1 / r2** を起動。ホストの UDP 10161/20161 を公開
  - `Dockerfile` — `frr`, `frr-snmp`, `snmpd` を導入
  
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

  推奨は dual-plane + L2 access のプロファイルです（ワンコマンド）。

  ```bash
  bash scripts/lab.sh up       # 起動（dual-plane + L2 access）
  bash scripts/lab.sh smoke    # IF/BGP/データプレーン/SNMP 確認
  bash scripts/lab.sh diag     # 競合診断
  bash scripts/lab.sh down     # 停止
  ```

  初期状態で eBGP ピアリングと最小広告が自動設定されます（下記「BGP（自動設定）」参照）。

  補足: dual-plane 構成ではホスト公開ポートは無効化されています（`ports: []`）。管理面 `mgmtnet` 側から SNMP を実行してください。

  ---

  参考（最小・単一ネット構成の例）:

  ```bash
  docker compose up -d --build
  bash scripts/show_frr_status.sh   # 起動確認（SNMP/BGP）
  ```

  初期状態では BGP セッションは Up ですが、経路広告はありません。`RM-OUT` / `RM-IN` は適用済みなので、
  ルータにネットワークを追加すると広告されます。

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

  ## 設計に合わせたカスタマイズ

  本ラボは環境変数で BGP/SNMP を可変化しました。Compose の `environment` で指定できます。

  - `MY_ASN` / `PEER_ASN` — 自AS / ピアAS
  - `PEER_IP` — ピアのIP（未指定時は `r1`/`r2` のDNS解決を使用）
  - `ADVERTISE_PREFIXES` — 広告するネットワーク（カンマ/スペース区切り）。例: `10.0.1.0/24,10.0.3.0/24`
  - `SNMP_ROCOMMUNITY` — SNMP の read-only community（既定 `public`）
  - `BGP_ROUTER_ID` — BGP Router-ID（例: 管理プレーンIP）
  - `BGP_UPDATE_SOURCE` — `neighbor ... update-source` に渡すIF名またはIP（任意）

  例（`docker-compose.yml` 既定値）:

  ```yaml
  services:
    r1:
      environment:
        - MY_ASN=65001
        - PEER_ASN=65002
        - SNMP_ROCOMMUNITY=public
        # - PEER_IP=172.19.0.2
        # - ADVERTISE_PREFIXES=10.0.1.0/24
    r2:
      environment:
        - MY_ASN=65002
        - PEER_ASN=65001
        - SNMP_ROCOMMUNITY=public
        # - PEER_IP=172.19.0.3
        # - ADVERTISE_PREFIXES=10.0.2.0/24
  ```

  ### 固定IP・複数IF + L2アクセス（推奨）

  ```bash
  # ワンコマンド起動/停止/検証
  bash scripts/lab.sh up        # 起動（dual-plane + L2 access）
  bash scripts/lab.sh smoke     # IF/BGP/データプレーン/SNMP 確認
  bash scripts/lab.sh diag      # 競合診断
  bash scripts/lab.sh down      # 停止
  ```

  - 管理面（mgmtnet）: 192.168.0.0/24 — r1=192.168.0.1, r2=192.168.0.2, l2a=192.168.0.11, l2b=192.168.0.12
  - サービス面（labnet）: 10.0.0.0/24 — r1=10.0.0.1, r2=10.0.0.2（eBGP）
  - VLAN: vlan10=10.0.10.0/24（r1 SVI=10.0.10.1, h10=10.0.10.100）, vlan20=10.0.20.0/24（r2 SVI=10.0.20.1, h20=10.0.20.100）

  ### BGP（自動設定）

  `docker-compose.dual-plane.yml` と `docker-compose.l2-access.yml` の合成で、r1/r2 の eBGP ピアと広告が自動設定されます。
  - r1: MY_ASN=65001, ADVERTISE_PREFIXES=10.0.10.0/24, PEER_IP=10.0.0.2
  - r2: MY_ASN=65002, ADVERTISE_PREFIXES=10.0.20.0/24, PEER_IP=10.0.0.1
  - 変更は Compose の `environment` で調整可（SoT に合わせて更新してください）

  補足:
  - 本リポで言う「オーバーレイ」は SDN のオーバーレイ網ではなく、Docker Compose のファイル合成（レイヤリング）を指します。
    ルーティング範囲や物理/論理IFの位置付けを記述し、意味付けしているだけです（厳密な平面分離はしません）。
  - `docker-compose.dual-plane.yml` はマスター設計として、管理/サービスの2面に加えて L2SW（`l2a`/`l2b`）も管理面に登場させています。
  - デフォルトの `docker-compose.yml` は SNMP をホストへ公開しますが、dual-plane では公開を無効化（ports: []）。
    管理面限定で SNMP を使う場合は、`mgmtnet` に接続した管理用コンテナから実行してください。

  ### L3スイッチ相当（L2セグメント + SVI をルータで表現）

  IETFサンプルの L3SW を、本環境では「複数の L2 セグメント（Linux bridge）に SVI を持つルータ」としてモデル化できます。

  - オーバーレイ: `docker-compose.l3sw.yml`
  - L2セグメント（VLAN相当）: `lan10`（10.0.10.0/24）, `lan20`（10.0.20.0/24）
  - ルータ間のトランジット: `transit`（198.51.100.0/24）で BGP ピアリング
  - 広告: R1 は `10.0.10.0/24`、R2 は `10.0.20.0/24`

  ```bash
  docker compose -f docker-compose.yml -f docker-compose.l3sw.yml up -d --build
  ```

  補足:
  - 各 Docker ネットワークは Linux bridge です（タグなしセグメント）。VLANタグやトランクは使っていません（必要なら別途 macvlan/802.1Q を検討）。
  - `lan10` / `lan20` にエンドホスト用のコンテナを追加すれば、L2 ドメイン内の疎通/デフォゲ検証が可能です。

  ### 共通4ノード（L3×2 + L2セグメント×2）プロファイル

  IETFモデルと整合する、管理192.168系 + サービス10系の共通化オーバーレイを用意しました。

  - オーバーレイ: `docker-compose.common-4node.yml`
  - 管理（mgmtnet）: 192.168.0.0/24 — r1=192.168.0.1, r2=192.168.0.2（Router-IDにも使用）
  - BGPトランジット（transit）: 10.0.0.0/30 — r1=10.0.0.2, r2=10.0.0.3（eBGPピア）
  - サービスL2セグメント: `lan10`=10.0.10.0/24（r1 SVI=10.0.10.1）, `lan20`=10.0.20.0/24（r2 SVI=10.0.20.1）
  - BGP AS: r1=64512 / r2=64513（必要に応じ変更可）

  ```bash
  docker compose -f docker-compose.yml -f docker-compose.common-4node.yml up -d --build
  ```

  使い分けの目安:
  - IETF側のサンプル（L3×2, L2×2）とアドレス整合を取りたい場合に最適。
  - より厳密な管理プレーン分離が必要な場合は、SNMPのホスト公開を外して `mgmtnet` 経由で監視。

  ### L2 スイッチ配下（アクセスのみ）

  L3 の配下に L2SW を置き、各 L2SW にアクセスポートだけを持たせる（L2A–L2B 間にトランクなし）モデルです。

  - オーバーレイ: `docker-compose.l2-access.yml`
  - VLAN: `vlan10`（10.0.10.0/24, GW 10.0.10.254）, `vlan20`（10.0.20.0/24, GW 10.0.20.254）
  - L3 SVI: r1=10.0.10.1（vlan10）, r2=10.0.20.1（vlan20）
  - アクセス: `h10`（vlan10 のみ, 10.0.10.100）→ L2A → R1、`h20`（vlan20 のみ, 10.0.20.100）→ L2B → R2

  ```bash
  docker compose -f docker-compose.yml -f docker-compose.dual-plane.yml -f docker-compose.l2-access.yml up -d --build
  ```

  注意:
  - Docker の bridge ネットワークでは 802.1Q タグは扱いません。本オーバーレイは VLAN を別ネットとして近似します。
  - L2A–L2B の直結はありません（各 VLAN は独立）。
  - ゲートウェイ IP は `.254` に寄せ、`.1` を L3 SVI に割り当てます。

  ## ポリシー（単一の真実源）

  - SoT: `policy/master.ietf.yaml`（RFC8345風トポロジ + `operational:*` 拡張で Compose/BGP/VLAN/SNMP を記述）
  - Compose/図の値は SoT に合わせて同期しています（更新時は SoT → 派生の順で）

  ## 依存関係

  - Docker（macOS は OrbStack 等で検証）
  - Net-SNMP CLI（`snmpwalk`）

  ## IETFスタイルのYAML（参考）

  IETF Network Topology（RFC 8345）に倣ったトポロジ表現と、デバイス別の `ietf-interfaces` 例を同梱しています（YANG-JSONのYAML表現）。

  - トポロジ（dual-plane）: `ietf/topology.dual-plane.yaml`
    - `service-plane`（198.51.100.0/24）/ `management-plane`（203.0.113.0/24）を別ネットとして記述
    - ノード `r1/r2` と各プレーンの終端点（termination-point）を定義
  - デバイス別IF定義: `ietf/r1-interfaces.yaml`, `ietf/r2-interfaces.yaml`

  注意:
  - 正式なIETFエンコードはJSON/XMLです。本リポのYAMLは共有・可読性のための便宜表現です。
  - 厳密なバリデータでの検証には JSON を推奨します（同ディレクトリに `.json` 版を同梱済み）。
    - `ietf/topology.dual-plane.json`
    - `ietf/r1-interfaces.json`, `ietf/r2-interfaces.json`

  ### Validator / ETL の使い方（外部リポ）

  例として、隣接リポジトリ `ietf-network-schema` のスクリプトを使った検証/抽出手順です。

  ```bash
  # 例: リポ配置
  #   ../ietf-network-schema/          （Validator/ETL）
  #   ./                              （このリポ: frr-snmp-lab）

  SCHEMA_REPO=../ietf-network-schema

  # 検証（YAMLをJSON Schemaでチェック）
  python3 "$SCHEMA_REPO/scripts/validate.py" \
    --schema "$SCHEMA_REPO/schema/schema.json" \
    --data ietf/topology.dual-plane.yaml

  # ETL（正規化JSONLへ抽出）
  python3 "$SCHEMA_REPO/scripts/etl.py" \
    --schema "$SCHEMA_REPO/schema/schema.json" \
    --data ietf/topology.dual-plane.yaml \
    --out ietf/objects.jsonl
  ```

  スキーマ差異メモ:
  - リンク終端は `ietf-network-topology:destination` 直下で `dest-node` / `dest-tp` を使用（`destination-node` 等では不可）。
  - 任意属性は `operational:*` 配下で拡張（例: `operational:tp-state`）。
  - 厳密なスキーマ適合を優先するため、YAML例は最小フィールドで記述しています。

  

  ### SNMP コミュニティを変えた場合

  `scripts/show_frr_status.sh` は環境変数 `SNMP_ROCOMMUNITY` を参照します。実行時に同じ値を指定しておくと一致します。
  ```bash
  SNMP_ROCOMMUNITY=mycomm bash scripts/show_frr_status.sh
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

  詳細な dual-plane + L2SW 構成の図は `topology.ascii.txt:1` を参照してください。
  > 上記 IP は一例です。実際のサブネットは `docker exec r1 ip -br a` などで確認してください。

  ## ライセンス

  MIT
