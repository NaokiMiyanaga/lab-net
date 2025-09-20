# 検証用ネットワーク（Frr,Linux Bridge,SNMP/AgentX)

Docker Compose 上で、ルータ2台（FRRouting）と L2 スイッチ2台（アクセスのみ）を用いた
管理・サービス・データの三つのプレーンを再現できる検証環境です。FRR は Net-SNMP（AgentX）経由で
BGP4-MIB を参照可能で、eBGP ピアリング、SVI、VLAN 相当の L2 セグメント、管理面限定の到達性といった
実運用に近い構成要素をコンパクトに試せます。設計の単一の真実源（SoT）は `policy/master.ietf.yaml` にあり、
Compose の各オーバーレイ（dual-plane / L2 access / L3SW など）は SoT と整合するように保っています。
macOS（OrbStack で検証）/ Docker で動作します。

## 事前準備（依存関係/ビルド）

  - 依存: Docker（macOS は OrbStack 推奨。Docker Desktop でも可）、Net-SNMP CLI（`snmpwalk` 任意）
  - ビルド: 初回の `lab.sh up` で自動ビルド。手動は `docker compose build` でも可
  - メモ: OrbStack は Docker+Linux VM を提供。アンインストールでスタックごと削除／Desktopへの切替も可
  - 主な構成物: `docker-compose.yml`（基本）, `docker-compose.dual-plane.yml` / `docker-compose.l2-access.yml`（推奨の組合せ）, `Dockerfile`

  
## 注意事項
- 主要サービスは `logging: none` を利用しており、ディスク肥大を防止しています。
  そのため `logs` コマンドはデバッグ用途として残していますが、空出力になる場合があります。
- SNMP の利用は管理プレーン (`mgmtnet`) を経由してください。
- BGP セッションや経路は `smoke` / `frr` コマンドで確認可能です。

## 初期セットアップ・テスト

  推奨は dual-plane + L2 access のプロファイル（ワンコマンド）。

  ```bash
  # ワンコマンド起動/停止/検証
  bash ctrl.sh up        # 起動（dual-plane + L2 access）
  bash ctrl.sh smoke     # IF/BGP/データプレーン/SNMP 確認
  bash ctrl.sh diag      # 競合診断
  bash ctrl.sh down      # 停止
  ```

  補足: dual-plane 構成ではホストへの SNMP 公開は無効（`ports: []`）。管理面 `mgmtnet` 側から SNMP を実行してください。

## 利用ガイド（USAGE）

  詳細な手順・プロファイル例・環境変数の一覧は、以下の利用ガイドに集約しました。
  - 日本語: docs/USAGE.ja.md
  - English: docs/USAGE.md

  ## メンテ / トラブルシュート

  - コンテナログ: `docker logs r1`（`/init/start.log` が継続表示されます）
  - AgentX ソケット: `docker exec -it r1 ss -xap | grep /var/agentx/master`
  - BGP が `(Policy)` の場合: ルートマップが適用済みか確認（init で自動適用）
  - SNMP コミュニティ変更時: `SNMP_ROCOMMUNITY=mycomm bash scripts/show_frr_status.sh`

## 設計ソース（SoT）と IETF モデル

  - SoT: `policy/master.ietf.yaml`（RFC 8345 風トポロジ + `operational:*` 拡張で Compose/BGP/VLAN/SNMP を記述）
  - IETFスタイルのサンプル: `ietf/topology.dual-plane.yaml`, `ietf/r1-interfaces.yaml`, `ietf/r2-interfaces.yaml`（JSON 版も同梱）

  ## ポートマッピング（ホスト → コンテナ）

  | ホスト UDP | コンテナ | 用途 |
  |---:|:---:|:---|
  | 10161 | r1:161/udp | r1 へ SNMP |
  | 20161 | r2:161/udp | r2 へ SNMP |

  ## トポロジ（ASCII）

  ```text
  Management plane (mgmtnet: 172.30.0.0/24)

      172.30.0.1             172.30.0.2           172.30.0.11         172.30.0.12
    +------------+           +------------+         +------------+       +------------+
    |    R1      |           |     R2     |         |    L2A     |       |    L2B     |
    | SNMP Agent |           | SNMP Agent |         |  snmpd     |       |  snmpd     |
    +------------+-----------+------------+---------+------------+-------+------------+
                 (mgmtnet: management-only reachability; SNMP via mgmt)

  Service plane (labnet: 10.0.0.0/24) — eBGP peering path

         10.0.0.1                                  10.0.0.2
    +----------------+   BGP (eBGP 65001-65002)   +----------------+
    |      R1        |<-------------------------->|       R2       |
    | bgpd + zebra   |                            | bgpd + zebra   |
    +----------------+                            +----------------+

  Data plane (VLANs as separate Docker bridges; no L2 trunk)

  vlan10 (10.0.10.0/24)                           vlan20 (10.0.20.0/24)
  GW .254 reserved; SVI on R1 .1                  GW .254 reserved; SVI on R2 .1

   +------+      access      +------+      access      +--------------------+
   | h10  |----------------->| L2A  |---------------->| R1 (SVI 10.0.10.1) |
   |10.0.10.100/24           +------+                 +--------------------+
   |GW→10.0.10.1                                                        
   +------+                                                               
  ```

  > IETF ネットワークモデルのトポロジに極力寄せた表現です。詳細は `topology.ascii.txt:1` も参照ください。
  > 上記 IP は一例です。実際のサブネットは `docker exec r1 ip -br a` などで確認してください。

  ## ライセンス

  このリポジトリは MIT ライセンスです。商用・非商用を問わずご利用いただけます。
  再利用・改変・配布の際は、著作権表示とライセンス表記の同梱にご協力ください。
