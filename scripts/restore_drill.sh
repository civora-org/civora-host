#!/bin/sh
# Restore drill: restore the latest backup into an ISOLATED throwaway compose
# project, verify against the backup manifest, record the result, tear down.
#
# Usage: scripts/restore_drill.sh [BACKUP_DIR]
#   BACKUP_DIR  defaults to the newest backups/<timestamp>/
#
# Isolation: separate compose project (civora-restore-drill), fresh volumes,
# random POSTGRES_PASSWORD, generated SECRET_KEY_BASE, ephemeral port.
# Result: appended to docs/ops/restore-drill-log.md (UTC date, duration,
# backup sha256, counts, PASS/FAIL). Quarterly policy + after any change to
# backup/restore scripts.
set -eu

cd "$(dirname "$0")/.."

START="$(date +%s)"
START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PROJECT="civora-restore-drill"
PORT="${PORT:-3100}"

BACKUP="${1:-}"
[ -n "$BACKUP" ] || BACKUP="$(ls -d backups/*/ 2>/dev/null | sort | tail -1)"
[ -n "$BACKUP" ] && [ -d "$BACKUP" ] || { echo "No backup found"; exit 1; }
echo "Drill: restore from $BACKUP"

cleanup() {
  docker compose -p "$PROJECT" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Isolated env: throwaway secrets, ephemeral port.
DRILL_PASSWORD="$(openssl rand -hex 16)"
DRILL_KEYBASE="$(openssl rand -hex 64)"
export DRILL_PASSWORD DRILL_KEYBASE PORT

verify_counts() {
  $DC exec -T db psql -U postgres -d decidim_app_production -Atc "
    SELECT 'organizations=' || count(*) FROM decidim_organizations
    UNION ALL SELECT 'users=' || count(*) FROM decidim_users
    UNION ALL SELECT 'attachments=' || count(*) FROM active_storage_attachments
    UNION ALL SELECT 'blobs=' || count(*) FROM active_storage_blobs;"
}

DC="docker compose -p $PROJECT -f compose.yaml -f compose.drill.yml"

echo "==> 1/5 Start isolated db"
$DC up -d db
for i in $(seq 1 30); do
  $DC exec -T db pg_isready -U postgres -q && break
  sleep 2
done

echo "==> 2/5 Restore database"
# The db service auto-creates POSTGRES_DB (decidim_app_production); restore
# into it. --clean --if-exists makes the restore re-runnable.
cat "$BACKUP/db.dump" | $DC exec -T db pg_restore -U postgres -d decidim_app_production --no-owner --no-privileges --clean --if-exists

echo "==> 3/5 Restore attachments"
docker volume create "${PROJECT}_app-storage" >/dev/null
docker run --rm -v "${PROJECT}_app-storage":/dst -v "$PWD/$BACKUP":/src:ro alpine \
  sh -c "tar xzf /src/storage.tar.gz -C /dst"

echo "==> 4/5 Start app and smoke check"
$DC up -d app
for i in $(seq 1 45); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/contracts" || true)"
  [ "$code" = "200" ] && break
  sleep 2
done

echo "==> 5/5 Verify counts against manifest"
ACTUAL="$(verify_counts)"
EXPECTED="$(ruby -rjson -e '
  m = JSON.parse(File.read(ARGV[0]))
  rc = m["row_counts"]
  puts %w[organizations users attachments blobs].map { |k| "#{k}=#{rc[k]}" }
' "$BACKUP/manifest.json")"

PASS=1
[ "$code" = "200" ] || PASS=0
[ "$ACTUAL" = "$EXPECTED" ] || PASS=0

echo "expected: $EXPECTED"
echo "actual:   $ACTUAL"
echo "http:     $code"

DURATION=$(( $(date +%s) - START ))
BACKUP_SHA="$(awk '{print $1}' "$BACKUP/sha256.txt" | head -1 | cut -c1-12)"
STATUS=$([ "$PASS" = "1" ] && echo PASS || echo FAIL)

LOG="docs/ops/restore-drill-log.md"
printf '| %s | %ss | %s | %s | %s | %s |\n' \
  "$START_UTC" "$DURATION" "$(basename "$BACKUP")" "$BACKUP_SHA" "$code" "$STATUS" >> "$LOG"

echo "Drill result: $STATUS (recorded in $LOG)"
exit "$PASS"
