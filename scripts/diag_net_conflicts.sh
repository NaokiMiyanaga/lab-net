#!/usr/bin/env bash
set -euo pipefail
for n in vlan10 vlan20 mgmtnet; do
  echo "[[ $n ]]"
  docker network inspect -f '{{.Name}}: {{range $k,$v := .Containers}}{{printf "%s " $v.Name}}{{end}}' "$n" 2>/dev/null || echo "(not found)"
done
