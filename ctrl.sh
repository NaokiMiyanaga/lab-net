#!/usr/bin/env bash
# --- ensure external shared network (mgmtnet) exists ---
ensure_mgmtnet() {
  if docker network inspect mgmtnet >/dev/null 2>&1; then
    return 0
  fi
  echo "[mgmtnet] create external shared network (172.30.0.0/24 via 172.30.0.254)"
  docker network create \
    --driver bridge \
    --subnet 172.30.0.0/24 \
    --gateway 172.30.0.254 \
    mgmtnet
}

set -euo pipefail

COMPOSE_FILE="docker-compose.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

cmd_build(){ compose build; }
cmd_up(){ compose up -d --build; }
cmd_down(){ compose down -v --remove-orphans || true; }
cmd_ps(){ compose ps; }
cmd_logs(){ compose logs -f --tail=200 "${@:-}"; }

cmd_rebuild(){
  read -r -p "This will DESTROY and rebuild the lab. Continue? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

  cmd_down

  # 残ネットワーク掃除
  for net in vlan10 vlan20 labnet mgmtnet; do
    docker network rm "$net" 2>/dev/null || true
  done
  docker network create mgmtnet 2>/dev/null || true

  compose build --no-cache
  cmd_up
  cmd_ps
}

# === 新規追加コマンド ===
cmd_diag(){
  bash "$SCRIPT_DIR/diag_net_conflicts.sh" "$@"
}

cmd_frr(){
  bash "$SCRIPT_DIR/show_frr_status.sh" "$@"
}

cmd_smoke(){
  bash "$SCRIPT_DIR/smoke_test.sh" "$@"
}

usage(){ cat <<'EOF'
Usage: lab.sh [build|up|down|rebuild|ps|logs|diag|frr|smoke]

  build     Build all images
  up        Bring up containers (with build)
  down      Stop and remove containers
  rebuild   Destroy and rebuild containers (with no-cache build)
  ps        Show container status
  logs      Follow logs
  diag      Run diag_net_conflicts.sh
  frr       Run show_frr_status.sh
  smoke     Run smoke_test.sh
EOF
}

case "${1:-}" in
  build)   shift; cmd_build "$@";;
  up)      shift; cmd_up "$@";;
  down)    shift; cmd_down "$@";;
  rebuild) shift; cmd_rebuild "$@";;
  ps)      shift; cmd_ps "$@";;
  logs)    shift; cmd_logs "$@";;
  diag)    shift; cmd_diag "$@";;
  frr)     shift; cmd_frr "$@";;
  smoke)   shift; cmd_smoke "$@";;
  ""|-h|--help) usage;;
  *) echo "unknown subcommand: $1"; usage; exit 1;;
esac