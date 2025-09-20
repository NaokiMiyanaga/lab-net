#!/usr/bin/env bash
# lab-net control
# shellcheck disable=SC2086
set -euo pipefail
IFS=$'\n\t'

# --- resolve project root (this file's directory) ---
THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$THIS_DIR"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
SCRIPTS_DIR="${SCRIPTS_DIR:-scripts}"
PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$THIS_DIR")}"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

# list services defined in this compose file
list_compose_services() {
  docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null || true
}

# detach potential endpoint names for our services from mgmtnet (preflight)
preflight_detach_mgmtnet() {
  if ! docker network inspect mgmtnet >/dev/null 2>&1; then
    return 0
  fi
  local svc
  for svc in $(list_compose_services); do
    # common name patterns: raw container_name, project-prefixed, underscore variant
    for candidate in "$svc" "${PROJECT}-${svc}" "${PROJECT}_${svc}_1"; do
      docker network disconnect -f mgmtnet "$candidate" 2>/dev/null || true
    done
  done
}

# list container names that belong to this compose project
list_project_containers() {
  docker ps -a --filter "label=com.docker.compose.project=${PROJECT}" --format '{{.Names}}'
}

# list endpoint/container names attached to a given docker network
list_network_endpoints() {
  local net="$1"
  docker network inspect -f '{{ range $k, $v := .Containers }}{{ $v.Name }} {{ end }}' "$net" 2>/dev/null
}

say() { printf "\033[1;36m[*]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

ensure_exec_scripts() {
  if [ -d "$SCRIPTS_DIR" ]; then
    chmod +x "$SCRIPTS_DIR"/*.sh 2>/dev/null || true
  fi
}

ensure_mgmtnet() {
  if docker network inspect mgmtnet >/dev/null 2>&1; then
    return 0
  fi
  say "create external network: mgmtnet (172.30.0.0/24 gw 172.30.0.254)"
  docker network create --driver bridge --subnet 172.30.0.0/24 --gateway 172.30.0.254 mgmtnet >/dev/null
}

# Disconnect all endpoints from a network then remove
nuke_network() {
  local net="$1"
  if ! docker network inspect "$net" >/dev/null 2>&1; then
    return 0
  fi
  warn "clean network endpoints: $net"
  # list container names attached to the network
  local names
  names="$(docker network inspect -f '{{ range $id, $c := .Containers }}{{ $c.Name }} {{ end }}' "$net" 2>/dev/null || true)"
  for n in $names; do
    docker network disconnect -f "$net" "$n" 2>/dev/null || true
  done
  say "remove network: $net"
  docker network rm "$net" >/dev/null 2>&1 || true
}

cleanup_networks() {
  nuke_network vlan10
  nuke_network vlan20
  # Do not remove mgmtnet by default since it's external/shared
}

# Disconnect all endpoints on an existing network (without removing it)
nuke_network_endpoints() {
  local net="$1"
  if ! docker network inspect "$net" >/dev/null 2>&1; then
    echo "[netfix] network not found: $net"
    return 0
  fi
  echo "[netfix] disconnect endpoints on $net"
  for n in $(docker network inspect -f '{{ range $k, $v := .Containers }}{{ $v.Name }} {{ end }}' "$net" 2>/dev/null); do
    docker network disconnect -f "$net" "$n" 2>/dev/null || true
  done
}

# Recreate mgmtnet safely: disconnect only this project's endpoints, then try rm/create.
recreate_mgmtnet_safe() {
  say "Recreating mgmtnet (safe)"
  preflight_detach_mgmtnet
  if docker network inspect mgmtnet >/dev/null 2>&1; then
    say "Disconnecting this project's endpoints from mgmtnet"
    for cname in $(list_project_containers); do
      docker network disconnect -f mgmtnet "$cname" 2>/dev/null || true
    done
    if docker network rm mgmtnet >/dev/null 2>&1; then
      say "Removed mgmtnet"
    else
      warn "Could not remove mgmtnet (probably in use). Keeping existing network."
      warn "Attached endpoints on mgmtnet: $(list_network_endpoints mgmtnet || true)"
      warn "Hint: stop those containers or run: docker network disconnect -f mgmtnet <name>"
      return 0
    fi
  fi
  docker network create --driver bridge --subnet 172.30.0.0/24 --gateway 172.30.0.254 mgmtnet >/dev/null
  say "mgmtnet created"
}

# Fix external mgmtnet: disconnect all endpoints and recreate the network
cmd_netfix(){
  recreate_mgmtnet_safe
  echo "[netfix] done"
}

cmd_build(){ ensure_exec_scripts; ensure_mgmtnet; compose build; }

cmd_up(){
  ensure_exec_scripts
  preflight_detach_mgmtnet
  ensure_mgmtnet
  compose up -d --build
  cmd_ps
}

cmd_down(){
  compose down -v --remove-orphans || true
}

cmd_rm(){
  compose rm -v || true
}

cmd_rebuild(){
  read -r -p "This will DESTROY and rebuild the lab. Continue? [y/N] " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
  cmd_down
  cmd_rm
  cleanup_networks
  preflight_detach_mgmtnet
  recreate_mgmtnet_safe
  compose build --no-cache
  cmd_up
}

cmd_ps(){ compose ps; }

cmd_logs(){
  # if services are passed, forward them; otherwise all logs
  if [ "$#" -gt 0 ]; then
    compose logs -f --tail=200 "$@"
  else
    compose logs -f --tail=200
  fi
}

cmd_health(){
  say "compose ps"
  compose ps || true
  echo
  say "container health (if any)"
  docker ps --format '{{.Names}}' | while read -r name; do
    state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$name" 2>/dev/null || echo n/a)"
    status="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo n/a)"
    printf "%-22s status=%-10s health=%s\n" "$name" "$status" "$state"
  done
}

run_script(){
  local f="$SCRIPTS_DIR/$1"; shift || true
  if [ ! -x "$f" ]; then
    err "missing or not executable: $f"; exit 1
  fi
  bash "$f" "$@"
}
cmd_diag(){  run_script "diag_net_conflicts.sh" "$@"; }
cmd_frr(){   run_script "show_frr_status.sh" "$@"; }
cmd_smoke(){ run_script "smoke_test.sh" "$@"; }

cmd_purge() {
  say "Stopping and removing all containers"
  compose down -v --remove-orphans || true
  compose rm -v || true

  say "Force removing project containers (project=${PROJECT})"
  for cname in $(list_project_containers); do
    docker rm -f "$cname" 2>/dev/null || true
  done

  if docker network inspect mgmtnet >/dev/null 2>&1; then
    say "Disconnecting this project's endpoints from mgmtnet"
    for cname in $(list_project_containers); do
      docker network disconnect -f mgmtnet "$cname" 2>/dev/null || true
    done
  fi

  say "Removing vlan10, vlan20, and mgmtnet networks if present"
  nuke_network vlan10
  nuke_network vlan20
  nuke_network mgmtnet

  say "Recreating mgmtnet network"
  docker network create --driver bridge --subnet 172.30.0.0/24 --gateway 172.30.0.254 mgmtnet >/dev/null

  say "Purge complete"
}

usage(){
  cat <<'EOF'
Usage: ./ctrl.sh <command> [args]

  build     Build all images            (ensure mgmtnet)
  up        Bring up containers         (build + ensure mgmtnet)
  down      Stop & remove containers
  rebuild   Destroy & rebuild (no-cache, cleans vlan10/20 and safely recreates mgmtnet)
  purge     Stop/remove all, clean networks (vlan10/20 + mgmtnet), recreate mgmtnet
  ps        Show container status
  logs      Follow logs (logs [service...])
  health    Show compose ps + container health brief
  netfix    Disconnect all endpoints on mgmtnet and recreate it

  diag      Run scripts/diag_net_conflicts.sh
  frr       Run scripts/show_frr_status.sh
  smoke     Run scripts/smoke_test.sh

Tips:
  - You can run this script from any directory; it auto-cd's to repo root.
  - If logs show "endpoint already exists in network vlanXX", run: ./ctrl.sh rebuild
  - If mgmtnet has stale endpoints (l2a/r2 etc), preflight detaches them automatically on up/rebuild.
EOF
}

case "${1:-}" in
  build)   shift; cmd_build "$@";;
  up)      shift; cmd_up "$@";;
  down)    shift; cmd_down "$@";;
  rebuild) shift; cmd_rebuild "$@";;
  purge)   shift; cmd_purge "$@";;
  ps)      shift; cmd_ps "$@";;
  logs)    shift; cmd_logs "$@";;
  health)  shift; cmd_health "$@";;
  netfix)  shift; cmd_netfix "$@";;
  diag)    shift; cmd_diag "$@";;
  frr)     shift; cmd_frr "$@";;
  smoke)   shift; cmd_smoke "$@";;
  ""|-h|--help) usage;;
  *) err "unknown subcommand: ${1:-}"; usage; exit 1;;
esac
