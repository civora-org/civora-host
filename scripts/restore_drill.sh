#!/bin/sh
# Restore drill: restore the latest backup into an ISOLATED throwaway compose
# project, verify against the backup manifest, record the result, tear down.
#
# Usage: scripts/restore_drill.sh [BACKUP_DIR]
#   BACKUP_DIR  defaults to the newest backups/<timestamp>/
#
# The backup's own SECRET_KEY_BASE is REQUIRED (civora-org/civora-platform#196):
# the backup holds data encrypted under it (admin TOTP seeds, Decidim
# authorizations), so a drill booted with any other key proves nothing. Supply
# it from the secrets backup, never from the repo:
#   DRILL_SECRET_KEY_BASE_FILE=/path/to/file   file holding just the value, or
#   DRILL_SECRET_KEY_BASE=...                  the value in the environment
# The value is never printed, logged or written anywhere by this script.
#
# Isolation: separate compose project (civora-restore-drill), fresh volumes,
# random POSTGRES_PASSWORD, ephemeral port, never the civora-host project.
# Checks: HTTP 200, row counts vs manifest, and a decrypt of encrypted rows
# (rake restore_drill:verify_encryption).
# Result: appended to docs/ops/restore-drill-log.md (UTC date, duration,
# backup sha256, HTTP, decrypt check, PASS/WARN/FAIL). Exit 0 = PASS,
# 1 = FAIL, 2 = WARN (no encrypted rows, so the key was not proven).
# Quarterly policy + after any change to backup/restore scripts.
set -eu

cd "$(dirname "$0")/.."

START="$(date +%s)"
START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PROJECT="${DRILL_PROJECT:-civora-restore-drill}"
PORT="${PORT:-3100}"
# The drill runs `down -v` on this project: it must never be the real stack.
case "$PROJECT" in
  civora-host*|civora-dec032*) echo "Refusing DRILL_PROJECT=$PROJECT: not a drill project"; exit 1 ;;
esac

# The backup's SECRET_KEY_BASE: from a file or the environment, never a default.
if [ -n "${DRILL_SECRET_KEY_BASE_FILE:-}" ]; then
  [ -r "$DRILL_SECRET_KEY_BASE_FILE" ] || { echo "DRILL_SECRET_KEY_BASE_FILE is not readable"; exit 1; }
  DRILL_KEYBASE="$(tr -d '\r\n' < "$DRILL_SECRET_KEY_BASE_FILE")"
else
  DRILL_KEYBASE="$(printf %s "${DRILL_SECRET_KEY_BASE:-}" | tr -d '\r\n')"
fi
if [ "${#DRILL_KEYBASE}" -lt 32 ]; then
  echo "The backup's SECRET_KEY_BASE is required: set DRILL_SECRET_KEY_BASE_FILE (or DRILL_SECRET_KEY_BASE)."
  echo "See docs/ops/restore-runbook.md. A random key would pass the HTTP and count checks but cannot decrypt the backup's data."
  exit 1
fi

BACKUP="${1:-}"
[ -n "$BACKUP" ] || BACKUP="$(ls -d backups/*/ 2>/dev/null | sort | tail -1)"
[ -n "$BACKUP" ] && [ -d "$BACKUP" ] || { echo "No backup found"; exit 1; }
echo "Drill: restore from $BACKUP"

cleanup() {
  docker compose -p "$PROJECT" down -v --remove-orphans >/dev/null 2>&1 || true
  # Created by hand in step 3, so `down -v` does not own it.
  docker volume rm "${PROJECT}_app-storage" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Isolated env: throwaway DB password, the backup's key, ephemeral port.
# POSTGRES_PASSWORD is exported so compose never interpolates the real .env one.
DRILL_PASSWORD="$(openssl rand -hex 16)"
POSTGRES_PASSWORD="$DRILL_PASSWORD"
export DRILL_PASSWORD DRILL_KEYBASE POSTGRES_PASSWORD PORT

verify_counts() {
  $DC exec -T db psql -U postgres -d decidim_app_production -Atc "
    SELECT 'organizations=' || count(*) FROM decidim_organizations
    UNION ALL SELECT 'users=' || count(*) FROM decidim_users
    UNION ALL SELECT 'attachments=' || count(*) FROM active_storage_attachments
    UNION ALL SELECT 'blobs=' || count(*) FROM active_storage_blobs;"
}

DC="docker compose -p $PROJECT -f compose.yaml -f compose.drill.yml"

echo "==> 1/6 Start isolated db"
$DC up -d db
for i in $(seq 1 30); do
  $DC exec -T db pg_isready -U postgres -q && break
  sleep 2
done

echo "==> 2/6 Restore database"
# The db service auto-creates POSTGRES_DB (decidim_app_production); restore
# into it. --clean --if-exists makes the restore re-runnable.
cat "$BACKUP/db.dump" | $DC exec -T db pg_restore -U postgres -d decidim_app_production --no-owner --no-privileges --clean --if-exists

echo "==> 3/6 Restore attachments"
docker volume create "${PROJECT}_app-storage" >/dev/null
docker run --rm -v "${PROJECT}_app-storage":/dst -v "$PWD/$BACKUP":/src:ro alpine \
  sh -c "tar xzf /src/storage.tar.gz -C /dst"

echo "==> 4/6 Start app and smoke check"
# --no-build: never (re)build, and so never retag, the stack's own image.
$DC up -d --no-build app
code=""
for i in $(seq 1 45); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/contracts" || true)"
  [ "$code" = "200" ] && break
  sleep 2
done

echo "==> 5/6 Decrypt encrypted rows with the backup's SECRET_KEY_BASE"
ENC_RC=0
ENC_OUT="$($DC exec -T app ./bin/rails restore_drill:verify_encryption 2>&1)" || ENC_RC=$?
# The check prints counts only; show just its summary line.
echo "$ENC_OUT" | grep '^encryption check' || echo "encryption check FAILED: no result (task did not run)"

echo "==> 6/6 Verify counts against manifest"
ACTUAL="$(verify_counts)"
EXPECTED="$(ruby -rjson -e '
  m = JSON.parse(File.read(ARGV[0]))
  rc = m["row_counts"]
  puts %w[organizations users attachments blobs].map { |k| "#{k}=#{rc[k]}" }
' "$BACKUP/manifest.json")"

PASS=1
[ "$code" = "200" ] || PASS=0
[ "$ACTUAL" = "$EXPECTED" ] || PASS=0
case "$ENC_RC" in
  0) ENC="decrypted" ;;
  3) ENC="none (warning)" ;;
  *) ENC="FAILED"; PASS=0 ;;
esac

echo "expected: $EXPECTED"
echo "actual:   $ACTUAL"
echo "http:     $code"
echo "decrypt:  $ENC"

DURATION=$(( $(date +%s) - START ))
BACKUP_SHA="$(awk '{print $1}' "$BACKUP/sha256.txt" | head -1 | cut -c1-12)"
# WARN: counts and HTTP fine, but no encrypted row existed, so the key is unproven.
if [ "$PASS" != "1" ]; then STATUS=FAIL; EXIT=1
elif [ "$ENC_RC" = "3" ]; then STATUS=WARN; EXIT=2
else STATUS=PASS; EXIT=0
fi

LOG="docs/ops/restore-drill-log.md"
printf '| %s | %ss | %s | %s | %s | %s | %s |\n' \
  "$START_UTC" "$DURATION" "$(basename "$BACKUP")" "$BACKUP_SHA" "$code" "$ENC" "$STATUS" >> "$LOG"

echo "Drill result: $STATUS (recorded in $LOG)"
exit "$EXIT"
