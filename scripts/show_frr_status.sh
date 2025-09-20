#!/usr/bin/env bash
set -euo pipefail
for c in r1 r2 l2a l2b h10 h20; do
  if docker inspect "$c" >/dev/null 2>&1; then
    echo "----- $c: frr -----"
    docker exec "$c" bash -lc 'vtysh -c "show version" || true'
  fi
done
