#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-lab-net}"
OLD_NET="192.168.0.0/24"
NEW_NET="${NEW_NET:-172.30.0.0/24}"
# host mapping: keep last octet, only swap first 3 octets
OLD_BASE="${OLD_BASE:-192.168.0}"
NEW_BASE="${NEW_BASE:-172.30.0}"
echo "[i] rewrite mgmt subnet: $OLD_NET -> $NEW_NET"
echo "[i] rewrite mgmt hosts : $OLD_BASE.X -> $NEW_BASE.X"

# target files
mapfile -t files < <(grep -rilE "(mgmt|mgmtnet|${OLD_BASE}\.)" "$ROOT" || true)

for f in "${files[@]}"; do
  cp -n "$f" "$f.bak" 2>/dev/null || true
  # subnet
  sed -i '' -e "s|${OLD_NET}|${NEW_NET}|g" "$f" 2>/dev/null || sed -i -e "s|${OLD_NET}|${NEW_NET}|g" "$f"
  # hosts (preserve last octet)
  for last in 1 2 11 12; do
    sed -i '' -E "s|\b${OLD_BASE}\.${last}\b|${NEW_BASE}.${last}|g" "$f" 2>/dev/null || \
    sed -i -E "s|\b${OLD_BASE}\.${last}\b|${NEW_BASE}.${last}|g" "$f"
  done
done

echo "[ok] rewrite complete. backups: *.bak"
