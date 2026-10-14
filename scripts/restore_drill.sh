#!/usr/bin/env bash
# Restore drill: restore the latest backup into an ISOLATED throwaway compose
# project, verify against the backup manifest, record the result, tear down.
#
# Usage: scripts/restore_drill.sh [BACKUP_DIR]
#        scripts/restore_drill.sh --offsite [STAMP|latest]
#   BACKUP_DIR  defaults to the newest backups/<timestamp>/
#   --offsite   first download the backup from the off-site target (the real
#               disaster path: nothing local is used), then drill it. STAMP
#               defaults to latest. The download goes to a temporary directory
#               under backups/ that is removed at the end.
#
# Encrypted backups (db.dump.age, storage.tar.gz.age; civora-org/civora-platform
# #167) need the age private key: BACKUP_AGE_IDENTITY_FILE=/path/to/key, a file
# on the machine you run the drill from, never on the production server. The
# artifacts are decrypted as a stream straight into pg_restore and tar, so no
# plaintext is written to disk.
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
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=lib/backup_env.sh
. scripts/lib/backup_env.sh
backup_env_load

OFFSITE=0
OFFSITE_STAMP=latest
BACKUP=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --offsite)
      OFFSITE=1
      if [ "$#" -gt 1 ] && [ "${2#-}" = "$2" ]; then OFFSITE_STAMP="$2"; shift; fi
      ;;
    -*) echo "usage: scripts/restore_drill.sh [BACKUP_DIR | --offsite [STAMP|latest]]"; exit 2 ;;
    *) BACKUP="$1" ;;
  esac
  shift
done

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

FETCHED=""
if [ "$OFFSITE" = "1" ]; then
  echo "==> 0/6 Download from the off-site target ($OFFSITE_STAMP)"
  mkdir -p backups
  chmod 700 backups
  FETCHED="$(mktemp -d backups/.drill-fetch.XXXXXX)"
  trap '[ -z "$FETCHED" ] || rm -rf "$FETCHED"' EXIT
  BACKUP="$(scripts/backup_fetch.sh "$OFFSITE_STAMP" "$FETCHED" | tail -1)"
  SOURCE="off-site"
else
  [ -n "$BACKUP" ] || BACKUP="$(ls -d backups/*/ 2>/dev/null | sort | tail -1)"
  SOURCE="local"
fi
[ -n "$BACKUP" ] && [ -d "$BACKUP" ] || { echo "No backup found"; exit 1; }
BACKUP="${BACKUP%/}"
echo "Drill: restore from $BACKUP ($SOURCE)"

# Integrity first: the checksums cover the stored (possibly encrypted) files.
(cd "$BACKUP" && shasum -a 256 -c sha256.txt) || { echo "Checksum mismatch: not drilling a corrupt backup"; exit 1; }

# Encrypted backup: needs the age private key, and must not start anything
# before knowing it is there.
ENCRYPTED=0
if [ -f "$BACKUP/db.dump.age" ]; then
  ENCRYPTED=1
  [ -n "${BACKUP_AGE_IDENTITY_FILE:-}" ] || { echo "This backup is encrypted: set BACKUP_AGE_IDENTITY_FILE to the age private key file."; exit 1; }
  [ -r "$BACKUP_AGE_IDENTITY_FILE" ] || { echo "BACKUP_AGE_IDENTITY_FILE is not readable"; exit 1; }
fi

# read_artifact NAME: the plaintext of db.dump or storage.tar.gz on stdout,
# decrypting on the fly when the backup is encrypted.
read_artifact() {
  if [ "$ENCRYPTED" = "1" ]; then
    backup_age_decrypt "$BACKUP_AGE_IDENTITY_FILE" < "$BACKUP/$1.age"
  else
    cat "$BACKUP/$1"
  fi
}

cleanup() {
  [ -z "$FETCHED" ] || rm -rf "$FETCHED"
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
read_artifact db.dump | $DC exec -T db pg_restore -U postgres -d decidim_app_production --no-owner --no-privileges --clean --if-exists

echo "==> 3/6 Restore attachments"
docker volume create "${PROJECT}_app-storage" >/dev/null
read_artifact storage.tar.gz | docker run --rm -i -v "${PROJECT}_app-storage":/dst alpine \
  tar xz -C /dst

echo "==> 4/6 Start app and smoke check"
# --no-build: never (re)build, and so never retag, the stack's own image.
$DC up -d --no-build app
code=""
for i in $(seq 1 45); do
  code="$(curl -sL -o /dev/null -w '%{http_code}' "http://localhost:$PORT/contracts" || true)"
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
LABEL="$(basename "$BACKUP")"
[ "$ENCRYPTED" = "1" ] && LABEL="$LABEL (encrypted)"
[ "$SOURCE" = "off-site" ] && LABEL="$LABEL (off-site)"
# WARN: counts and HTTP fine, but no encrypted row existed, so the key is unproven.
if [ "$PASS" != "1" ]; then STATUS=FAIL; EXIT=1
elif [ "$ENC_RC" = "3" ]; then STATUS=WARN; EXIT=2
else STATUS=PASS; EXIT=0
fi

LOG="docs/ops/restore-drill-log.md"
printf '| %s | %ss | %s | %s | %s | %s | %s |\n' \
  "$START_UTC" "$DURATION" "$LABEL" "$BACKUP_SHA" "$code" "$ENC" "$STATUS" >> "$LOG"

echo "Drill result: $STATUS (recorded in $LOG)"
exit "$EXIT"
