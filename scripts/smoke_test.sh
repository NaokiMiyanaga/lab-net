#!/usr/bin/env bash
set -Eeuo pipefail

# ---- timeout/gtimeout の検出（必ず配列として宣言）----
declare -a TIMEOUT=()
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT=(timeout -k 2 20)
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT=(gtimeout -k 2 20)
else
  echo "[!] timeout not found; long runs may block"
fi

# ---- 対象ノード（環境変数 NODES / 引数で上書き可）----
# 例) NODES='r1 r2' ./ctrl.sh smoke  または  ./ctrl.sh smoke r1 r2
declare -a NODES_ARR=()
if [[ "${NODES-}" != "" ]]; then
  # shellcheck disable=SC2206
  NODES_ARR=(${NODES})
elif (( $# > 0 )); then
  # shellcheck disable=SC2206
  NODES_ARR=($@)
else
  NODES_ARR=(r1 r2 l2a l2b h10 h20)
fi

# ---- ユーティリティ ----
line() { printf '%s\n' "============================================================"; }
is_running() {
  local n="$1"
  docker inspect -f '{{.State.Running}}' "$n" 2>/dev/null | grep -q true
}

dex() {
  # docker exec ラッパ：起動確認 & timeout があれば使用
  local n="$1"; shift
  if ! is_running "$n"; then
    echo "[$n] not running"
    return 1
  fi
  if ((${#TIMEOUT[@]} > 0)); then
    "${TIMEOUT[@]}" docker exec -i "$n" bash -lc "$*" 2>&1
  else
    docker exec -i "$n" bash -lc "$*" 2>&1
  fi
}

smoke_node() {
  local n="$1"
  echo
  line
  echo "[ $n ] basic info"

  # NIC 概要（失敗しても落とさない）
  dex "$n" "ip -br a || true"

  # FRR が居るなら経路表示
  dex "$n" "command -v vtysh >/dev/null 2>&1 && vtysh -c 'show ip route' || true"
}

# ---- 実行 ----
for n in "${NODES_ARR[@]}"; do
  smoke_node "$n" || true
done