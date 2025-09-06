#!/usr/bin/env bash
set -euo pipefail

# Lab control script: generate overlays, rebuild lab (destructive), and validate via wrapper.
# - Removes r1 r2 l2a l2b h10 h20 if present
# - Ensures external network `mgmtnet`
# - Generates overlays (non-destructive to originals):
#     * docker-compose.mcp-migrate.override.yml (standardize networks/containers/L2 caps)
#     * docker-compose.hosts.yml (h10/h20)
# - Brings up r1 r2 l2a l2b h10 h20 with overlays
# - Runs wrapper validation (optionally --skip-bridge / --no-validate)
#
# Usage:
#   bash scripts/rebuild_all.sh --lab-dir /path/to/lab-net \
#     [--wrapper-dir /path/to/mcp-ansible-wrapper] [--skip-bridge] [--no-validate]
#   # オーバーレイ生成のみ:
#   bash scripts/rebuild_all.sh --lab-dir /path/to/lab-net --generate-only

LAB_DIR="${LAB_DIR:-}"
WRAPPER_DIR="${WRAPPER_DIR:-}"
SKIP_BRIDGE=${SKIP_BRIDGE:-0}
NONINTERACTIVE=0
NO_VALIDATE=0
GEN_ONLY=0

# Load defaults from repo-root .env if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$REPO_ROOT/.env"
  set +a
  LAB_DIR="${LAB_DIR:-${LAB_DIR:-}}"
  WRAPPER_DIR="${WRAPPER_DIR:-${WRAPPER_DIR:-}}"
  SKIP_BRIDGE=${SKIP_BRIDGE:-0}
fi

# Helpers
normalize_path() { eval echo "$1"; }

update_env() {
  local key="$1" val="$2" env_file="$REPO_ROOT/.env"
  mkdir -p "$REPO_ROOT" >/dev/null 2>&1 || true
  touch "$env_file"
  if grep -qE "^${key}=" "$env_file"; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$env_file" || true
  else
    printf "%s=%s\n" "$key" "$val" >> "$env_file"
  fi
}

search_under_home() {
  local name="$1"
  find "$HOME" -maxdepth 4 -type d -name "$name" 2>/dev/null | sort -u
}

prompt_dir() {
  local var="$1" default_name="$2" current="$3" detected sel def
  if [[ "$NONINTERACTIVE" -ne 0 || ! -t 0 ]]; then
    echo "$current"; return 0
  fi
  def=""
  if [[ -n "$current" ]]; then
    def="$current"
  else
    detected=()
    while IFS= read -r line; do detected+=("$line"); done < <(search_under_home "$default_name")
    if [[ ${#detected[@]} -eq 1 ]]; then def="${detected[0]}"; fi
  fi
  if [[ -n "$def" ]]; then
    read -rp "[input] ${var} を入力してください (Enterで ${def}): " sel || true
    sel=${sel:-$def}
  else
    read -rp "[input] ${var} を入力してください: " sel || true
  fi
  sel=$(normalize_path "$sel")
  echo "$sel"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lab-dir) LAB_DIR="$2"; shift 2;;
    --wrapper-dir) WRAPPER_DIR="$2"; shift 2;;
    --skip-bridge) SKIP_BRIDGE=1; shift;;
    --non-interactive|--no-prompt) NONINTERACTIVE=1; shift;;
    --no-validate) NO_VALIDATE=1; shift;;
    --generate-only) GEN_ONLY=1; shift;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "$LAB_DIR" ]]; then
  LAB_DIR=$(prompt_dir LAB_DIR lab-net "")
  if [[ -z "$LAB_DIR" ]]; then
    echo "[error] LAB_DIR が未指定です（.env/環境変数/引数で指定可能）" >&2
    exit 1
  fi
  if [[ "$NONINTERACTIVE" -eq 0 && -t 0 ]]; then
    read -rp "[save] LAB_DIR を .env に保存しますか? [Y/n]: " ans || true
    ans=${ans:-Y}
    [[ "$ans" =~ ^[Yy]$ ]] && update_env LAB_DIR "$LAB_DIR"
  fi
fi

# Resolve wrapper dir default to this repo root (script/..)
if [[ -z "$WRAPPER_DIR" ]]; then
  # Try repo root as default
  local_default="$(cd "$SCRIPT_DIR/.." && pwd)"
  WRAPPER_DIR=$(prompt_dir WRAPPER_DIR mcp-ansible-wrapper "$local_default")
  if [[ -z "$WRAPPER_DIR" ]]; then WRAPPER_DIR="$local_default"; fi
  if [[ "$NONINTERACTIVE" -eq 0 && -t 0 ]]; then
    read -rp "[save] WRAPPER_DIR を .env に保存しますか? [Y/n]: " ans2 || true
    ans2=${ans2:-Y}
    [[ "$ans2" =~ ^[Yy]$ ]] && update_env WRAPPER_DIR "$WRAPPER_DIR"
  fi
fi

# Tilde/env expansion and canonicalization
LAB_DIR="$(normalize_path "$LAB_DIR")"
WRAPPER_DIR="$(normalize_path "$WRAPPER_DIR")"

echo "[info] LAB_DIR=${LAB_DIR} WRAPPER_DIR=${WRAPPER_DIR}"

cd "$LAB_DIR"

echo "[step] Ensure external network 'mgmtnet'"
if docker network inspect mgmtnet >/dev/null 2>&1; then
  echo " - mgmtnet already exists"
else
  docker network create mgmtnet
fi

echo "[step] Generate overlays (standardize L2, networks; create hosts overlay)"
# Pick non-overlapping subnets for VLANs
existing_subnets=$(docker network inspect $(docker network ls -q) -f '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' 2>/dev/null || true)
overlaps() { grep -qx "$1" <<<"$existing_subnets" 2>/dev/null; }
choose_subnet() {
  local def="$1"; shift; local cand
  for cand in "$def" "$@"; do
    if ! overlaps "$cand"; then echo "$cand"; return 0; fi
  done
  echo "$def"
}
VLAN10_SN=$(choose_subnet "${VLAN10_SUBNET:-10.0.10.0/24}" 10.10.10.0/24 10.0.110.0/24 172.20.10.0/24)
VLAN20_SN=$(choose_subnet "${VLAN20_SUBNET:-10.0.20.0/24}" 10.20.20.0/24 10.0.120.0/24 172.20.20.0/24)
gw_from_subnet() { local s="$1"; s="${s%/*}"; IFS=. read -r a b c d <<< "$s"; echo "$a.$b.$c.254"; }
VLAN10_GW=$(gw_from_subnet "$VLAN10_SN")
VLAN20_GW=$(gw_from_subnet "$VLAN20_SN")
# Standardize overlay (networks/container_name/L2 caps)
overlay="${LAB_DIR}/docker-compose.mcp-migrate.override.yml"
cat >"${overlay}" <<YAML
# Generated by lab control (do not commit if temporary)
services:
  r1:
    container_name: r1
  r2:
    container_name: r2
  l2a:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: l2a
    cap_add:
      - NET_ADMIN
    command: ["bash", "-lc", "/init/l2-init.sh || true; sleep infinity"]
    restart: unless-stopped
  l2b:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: l2b
    cap_add:
      - NET_ADMIN
    command: ["bash", "-lc", "/init/l2-init.sh || true; sleep infinity"]
    restart: unless-stopped

networks:
  mgmtnet:
    name: mgmtnet
  labnet:
    name: labnet
  vlan10:
    name: vlan10
    driver: bridge
    ipam:
      config:
        - subnet: ${VLAN10_SN}
          gateway: ${VLAN10_GW}
  vlan20:
    name: vlan20
    driver: bridge
    ipam:
      config:
        - subnet: ${VLAN20_SN}
          gateway: ${VLAN20_GW}
YAML

# Hosts overlay (if missing) for h10/h20
hosts_overlay="${LAB_DIR}/docker-compose.hosts.yml"
# Always (re)generate hosts overlay without static IPs to avoid subnet mismatch
# Derive SVI addresses (.1) from VLAN subnets
svi_from_subnet() { local s="$1"; s="${s%/*}"; IFS=. read -r a b c d <<< "$s"; echo "$a.$b.$c.1"; }
VLAN10_SVI=$(svi_from_subnet "$VLAN10_SN")
VLAN20_SVI=$(svi_from_subnet "$VLAN20_SN")
cat >"${hosts_overlay}" <<YAML
services:
  h10:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: h10
    command: ["bash", "-lc", "ip route del default || true; ip route add default via ${VLAN10_SVI} dev eth0 || true; sleep infinity"]
    networks:
      vlan10: {}

  h20:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: h20
    command: ["bash", "-lc", "ip route del default || true; ip route add default via ${VLAN20_SVI} dev eth0 || true; sleep infinity"]
    networks:
      vlan20: {}
YAML

if [[ "$GEN_ONLY" -eq 1 ]]; then
  echo "[done] Overlays generated at: $overlay and ${hosts_overlay}"
  exit 0
fi

echo "[step] Remove existing containers (ignore if missing)"
docker rm -f r1 r2 l2a l2b h10 h20 >/dev/null 2>&1 || true

echo "[step] Remove old VLAN networks (ignore if missing)"
docker network rm vlan10 vlan20 >/dev/null 2>&1 || true

COMPOSE_FILES=(
  "docker-compose.yml"
  "docker-compose.dual-plane.yml"
  "docker-compose.l2-access.yml"
  "docker-compose.mcp-migrate.override.yml"
  "docker-compose.hosts.yml"
)

echo "[step] Bring up lab services (r1 r2 l2a l2b h10 h20)"
docker compose \
  -f "${COMPOSE_FILES[0]}" \
  -f "${COMPOSE_FILES[1]}" \
  -f "${COMPOSE_FILES[2]}" \
  -f "$overlay" \
  -f "$hosts_overlay" \
  up -d --build --force-recreate r1 r2 l2a l2b h10 h20

if [[ "$NO_VALIDATE" -eq 0 ]]; then
  echo "[step] Validate via wrapper"
  cd "$WRAPPER_DIR"
  docker compose -f compose.yaml build
  if [[ -x "scripts/validate.sh" ]]; then
    if [[ "$NONINTERACTIVE" -eq 0 && -t 0 ]]; then
      read -rp "[run] wrapper/scripts/validate.sh を実行しますか? [Y/n]: " runv || true
      runv=${runv:-Y}
      if [[ "$runv" =~ ^[Yy]$ ]]; then
        if [[ $SKIP_BRIDGE -eq 1 ]]; then
          bash scripts/validate.sh --skip-bridge
        else
          bash scripts/validate.sh
        fi
      else
        echo "[skip] wrapper validation (user choice)"
      fi
    else
      # non-interactive: run by default
      if [[ $SKIP_BRIDGE -eq 1 ]]; then
        bash scripts/validate.sh --skip-bridge
      else
        bash scripts/validate.sh
      fi
    fi
  else
    echo "[skip] wrapper validation: scripts/validate.sh not found"
  fi
else
  echo "[skip] wrapper validation (requested)"
fi

echo "[done] Rebuild and validation completed."
