#!/bin/sh
# Prune backups by retention: keep BACKUP_RETENTION_DAYS (default 30) of daily
# backups, locally and off-site (civora-org/civora-platform#167, DPA annex 1).
#
# Usage: scripts/backup_prune.sh [BACKUP_DEST]
#
# The old 7 daily / 4 weekly / 6 monthly tiers are gone on purpose: the DPA
# promises deletion of backups after the retention period, and a six-month
# monthly tier would keep personal data for six months. The newest backup is
# never removed, whatever its age (see scripts/lib/backup_retention.sh), so a
# run of failed backups cannot prune the last good copy.
#
# Off-site expiry runs here too, over the same S3-compatible target as
# scripts/backup_offsite.sh. If the bucket has its own lifecycle rule, set
# BACKUP_OFFSITE_PRUNE=0 and let the provider expire objects (the credentials
# then need no delete permission).
set -eu

cd "$(dirname "$0")/.."

# shellcheck source=lib/backup_env.sh
. scripts/lib/backup_env.sh
# shellcheck source=lib/backup_retention.sh
. scripts/lib/backup_retention.sh
backup_env_load

DEST="${1:-backups}"
removed=0

if [ -d "$DEST" ]; then
  for stamp in $(ls "$DEST" | backup_expired_stamps); do
    [ -d "$DEST/$stamp" ] || continue
    echo "prune local: $stamp"
    rm -rf "${DEST:?}/$stamp"
    removed=$((removed + 1))
  done
else
  echo "No backup dir: $DEST"
fi
echo "Pruned $removed local backup(s) from $DEST (retention ${BACKUP_RETENTION_DAYS}d)"

if backup_offsite_configured && [ "${BACKUP_OFFSITE_PRUNE:-1}" != "0" ]; then
  remote="$(backup_remote_base)"
  listing="$(backup_rclone lsf --dirs-only "$remote")" || { echo "ERROR: cannot list $remote"; exit 1; }
  remote_removed=0
  for stamp in $(printf '%s\n' "$listing" | sed 's|/$||' | backup_expired_stamps); do
    echo "prune off-site: $stamp"
    backup_rclone purge "$remote/$stamp" || { echo "ERROR: could not delete $remote/$stamp"; exit 1; }
    remote_removed=$((remote_removed + 1))
  done
  echo "Pruned $remote_removed off-site backup(s) (retention ${BACKUP_RETENTION_DAYS}d)"
fi
