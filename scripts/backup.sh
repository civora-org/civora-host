#!/bin/sh
# Create a full backup: Postgres dump + attachments tar + manifest.json.
#
# Usage: scripts/backup.sh [BACKUP_DEST]
#   BACKUP_DEST  target dir (default: ./backups, gitignored, created 0700)
#
# Runs pg_dump INSIDE the db container (postgres:17 client — no version skew)
# and tars the app-storage volume. A manifest.json records timestamp, image
# tag, git SHA, row counts and sha256 of each artifact; the restore drill
# verifies against it. Schedule via cron (see docs/ops/restore-runbook.md).
set -eu

cd "$(dirname "$0")/.."

DEST="${1:-backups}"
mkdir -p "$DEST"
chmod 700 "$DEST"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$DEST/$STAMP"
mkdir -p "$OUT"

COMPOSE="docker compose"

echo "==> Postgres dump"
$COMPOSE exec -T db pg_dump -Fc -U postgres decidim_app_production \
  > "$OUT/db.dump"

echo "==> Attachments (app-storage volume)"
docker run --rm -v civora-host_app-storage:/src:ro -v "$PWD/$OUT":/out alpine \
  tar czf /out/storage.tar.gz -C /src .

echo "==> Manifest"
IMAGE_TAG="$(docker inspect -f '{{.Config.Image}}' "$($COMPOSE ps -q app)" 2>/dev/null || echo unknown)"
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

# Row counts of verification-relevant tables, taken via a throwaway psql.
$COMPOSE exec -T db psql -U postgres -d decidim_app_production -Atc "
  SELECT 'organizations='  || count(*) FROM decidim_organizations
  UNION ALL SELECT 'users='         || count(*) FROM decidim_users
  UNION ALL SELECT 'attachments='   || count(*) FROM active_storage_attachments
  UNION ALL SELECT 'blobs='         || count(*) FROM active_storage_blobs;
" > "$OUT/row_counts.txt"

{
  echo "{"
  echo "  \"timestamp\": \"$STAMP\","
  echo "  \"image_tag\": \"$IMAGE_TAG\","
  echo "  \"git_sha\": \"$GIT_SHA\","
  echo "  \"postgres_major\": 17,"
  echo "  \"row_counts\": {"
  awk -F= 'NR>1 {printf ",\n"} {printf "    \"%s\": %s", $1, $2}' "$OUT/row_counts.txt"
  echo ""
  echo "  }"
  echo "}"
} > "$OUT/manifest.json"

echo "==> Checksums"
(cd "$OUT" && shasum -a 256 db.dump storage.tar.gz > sha256.txt)

echo "Backup written to $OUT"
cat "$OUT/manifest.json"
