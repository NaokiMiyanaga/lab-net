#!/usr/bin/env bash
set -euo pipefail

# Simple helper to compose the lab
# Usage:
#   scripts/lab.sh up        # build & start (dual-plane + L2 access)
#   scripts/lab.sh down      # stop & remove
#   scripts/lab.sh restart   # down + up
#   scripts/lab.sh smoke     # run smoke tests
#   scripts/lab.sh diag      # diagnose address conflicts
#   scripts/lab.sh status    # show containers
#   scripts/lab.sh logs r1   # tail logs for a node (r1/r2/l2a/l2b/h10/h20)

COMPOSE=(
  -f docker-compose.yml
  -f docker-compose.dual-plane.yml
  -f docker-compose.l2-access.yml
)

cmd=${1:-}
shift || true

case "$cmd" in
  up)
    docker compose "${COMPOSE[@]}" up -d --build
    ;;
  down)
    docker compose "${COMPOSE[@]}" down
    ;;
  restart)
    docker compose "${COMPOSE[@]}" down
    docker compose "${COMPOSE[@]}" up -d --build
    ;;
  smoke)
    bash scripts/smoke_test.sh
    ;;
  diag)
    bash scripts/diag_net_conflicts.sh
    ;;
  status)
    docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}'
    ;;
  logs)
    if [[ $# -lt 1 ]]; then echo "usage: scripts/lab.sh logs <container>"; exit 1; fi
    docker logs -f "$1"
    ;;
  *)
    cat <<USAGE
Usage:
  scripts/lab.sh up|down|restart|smoke|diag|status|logs <name>

Compose files:
  docker-compose.yml + docker-compose.dual-plane.yml + docker-compose.l2-access.yml
USAGE
    exit 1
    ;;
esac

