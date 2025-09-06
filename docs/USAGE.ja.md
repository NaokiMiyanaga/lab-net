# 利用ガイド（日本語）

このドキュメントは、検証用ネットワーク（Frr, Linux Bridge, SNMP/AgentX）の詳細な使い方をまとめています。

## 推奨プロファイル（dual-plane + L2 access）

- 管理面: mgmtnet=192.168.0.0/24（r1=.1, r2=.2, l2a=.11, l2b=.12）
- サービス面: labnet=10.0.0.0/24（r1=.1, r2=.2）
- データ面: vlan10=10.0.10.0/24（R1 SVI .1, h10 .100）/ vlan20=10.0.20.0/24（R2 SVI .1, h20 .100）

起動は `bash scripts/lab.sh up`（内部で dual-plane + L2 access を合成）

## それぞれ 1 プレフィックスを広告

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

メモ: RIB に経路を作るため必要ならブラックホールルートを追加（例: `ip route add 10.0.1.0/24 dev lo`）

## BGP の確認

```bash
docker exec -it r1 vtysh -c 'show ip bgp summary'
docker exec -it r2 vtysh -c 'show ip bgp summary'

docker exec -it r1 vtysh -c 'show ip route bgp'
docker exec -it r2 vtysh -c 'show ip route bgp'
```

## SNMP の確認

ホスト公開時（単一ネット構成など）:

```bash
snmpwalk -v2c -c public 127.0.0.1:10161 1.3.6.1.2.1.15.3.1 | head   # r1
snmpwalk -v2c -c public 127.0.0.1:20161 1.3.6.1.2.1.15.3.1 | head   # r2
```

コンテナ内:

```bash
docker exec -it r1 snmpwalk -v2c -c public 127.0.0.1:161 1.3.6.1.2.1.15.3.1 | head
```

dual-plane ではホスト公開は無効（`ports: []`）。`mgmtnet` 側から実行してください。

## 設計に合わせたカスタマイズ（環境変数）

- `MY_ASN` / `PEER_ASN`（自AS/ピアAS）
- `PEER_IP`（ピアのIP）
- `ADVERTISE_PREFIXES`（広告プレフィックス。例: `10.0.1.0/24,10.0.3.0/24`）
- `SNMP_ROCOMMUNITY`（既定 `public`）
- `BGP_ROUTER_ID`, `BGP_UPDATE_SOURCE`

Compose 例（抜粋）:

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

## その他のプロファイル

- L3スイッチ相当（複数 L2 + SVI）

```bash
docker compose -f docker-compose.yml -f docker-compose.l3sw.yml up -d --build
```

- 共通4ノード（L3×2 + L2×2）

```bash
docker compose -f docker-compose.yml -f docker-compose.common-4node.yml up -d --build
```

## L2 スイッチ配下（アクセスのみ）

L3 配下に L2SW を置き、各 L2SW にアクセスポートのみ（L2A–L2B 間にトランクなし）。

```bash
docker compose -f docker-compose.yml -f docker-compose.dual-plane.yml -f docker-compose.l2-access.yml up -d --build
```

注意:
- Docker の bridge ネットワークは 802.1Q タグを扱いません（VLAN は別ネットで近似）。
- L2A–L2B の直結はありません（各 VLAN は独立）。
- ゲートウェイ IP は `.254` を予約し、`.1` を L3 SVI に割当。

