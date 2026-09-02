#!/bin/sh
# Prune backups by retention: keep 7 daily / 4 weekly / 6 monthly.
# A backup "slot" is identified by its UTC timestamp dir name (YYYYmmddTHHMMSSZ).
#
# Usage: scripts/backup_prune.sh [BACKUP_DEST]
#
# Caveat (threat-model retention): pruning must never remove the LAST copy
# of audit-relevant data — audit trail is permanent, drafts >=5y. This script
# only prunes local copies; keep at least one offsite copy before relying on
# any single retention tier.
set -eu

cd "$(dirname "$0")/.."

DEST="${1:-backups}"
[ -d "$DEST" ] || { echo "No backup dir: $DEST"; exit 0; }

now_epoch="$(date -u +%s)"
removed=0

for dir in "$DEST"/*/; do
  [ -d "$dir" ] || continue
  stamp="$(basename "$dir")"
  case "$stamp" in
    ????????T??????Z) ;;
    *) continue ;;
  esac
  d="${stamp%%T*}"; t="${stamp#*T}"; t="${t%Z}"
  epoch="$(date -u -j -f "%Y%m%d%H%M%S" "$d$t" +%s 2>/dev/null || \
           date -u -d "${d} ${t:0:2}:${t:2:2}:${t:4:2}" +%s 2>/dev/null || echo 0)"
  [ "$epoch" -eq 0 ] && continue

  age_days=$(( (now_epoch - epoch) / 86400 ))

  # Keep tiers: everything <7d; same-ISO-week <28d; first-of-month <180d.
  keep=0
  if [ "$age_days" -lt 7 ]; then
    keep=1
  elif [ "$age_days" -lt 28 ]; then
    # keep Mondays (weekly tier)
    [ "$(date -u -r "$epoch" +%u 2>/dev/null || date -u -d "@$epoch" +%u)" = "1" ] && keep=1
  elif [ "$age_days" -lt 180 ]; then
    [ "${d#????}" = "0101" ] || [ "$(date -u -r "$epoch" +%d 2>/dev/null || date -u -d "@$epoch" +%d)" = "01" ] && keep=1
  fi

  if [ "$keep" -eq 0 ]; then
    echo "prune: $stamp (age ${age_days}d)"
    rm -rf "$dir"
    removed=$((removed + 1))
  fi
done

echo "Pruned $removed backup(s) from $DEST"
