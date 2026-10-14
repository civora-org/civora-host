#!/usr/bin/env bash
# Create a full backup: Postgres dump + attachments tar + manifest.json,
# encrypted with age, then copied off-site (civora-org/civora-platform#167).
#
# Usage: scripts/backup.sh [BACKUP_DEST]
#   BACKUP_DEST  target dir (default: ./backups, gitignored, created 0700)
#
# Runs pg_dump INSIDE the db container (postgres:17 client, no version skew)
# and tars the app-storage volume. With BACKUP_AGE_RECIPIENTS set, both streams
# are piped through age on the way to disk: no plaintext copy ever exists on
# this machine, and the private key is not here at all, so a stolen disk or a
# stolen bucket yields nothing. A manifest.json records timestamp, image tag,
# git SHA, row counts and the sha256 of each stored artifact; the restore drill
# verifies against it. Without recipients the backup is plaintext and the
# script says so loudly; BACKUP_STRICT=1 (the pilot setting) refuses that.
# Off-site: see scripts/backup_offsite.sh. Schedule via cron (see
# docs/ops/restore-runbook.md).
#
# Compose project: COMPOSE_PROJECT_NAME (default civora-host, the name in
# compose.yaml), so a throwaway stack can be backed up by naming its project.
set -euo pipefail

cd "$(dirname "$0")/.."

# Files are created 0600 under a 0700 directory: backups are secret material.
umask 077

# shellcheck source=lib/backup_env.sh
. scripts/lib/backup_env.sh
backup_env_load

DEST="${1:-backups}"

ENCRYPT=0
backup_encryption_configured && ENCRYPT=1

if [ "${BACKUP_STRICT:-0}" = "1" ]; then
  # Check before doing any work: a strict stack must never produce a backup
  # that is plaintext or that stays on this machine.
  [ "$ENCRYPT" = "1" ] || { echo "ERROR: BACKUP_STRICT=1 but BACKUP_AGE_RECIPIENTS is empty: refusing a plaintext backup"; exit 1; }
  backup_offsite_configured || { echo "ERROR: BACKUP_STRICT=1 but BACKUP_OFFSITE_BUCKET is empty: refusing a backup that stays on this machine"; exit 1; }
fi

mkdir -p "$DEST"
chmod 700 "$DEST"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$DEST/$STAMP"
mkdir -p "$OUT"
# Anything written to $OUT is partial until the manifest exists: a failed run
# leaves no half backup behind to be mistaken for the latest one.
trap 'rc=$?; if [ "$rc" -ne 0 ] && [ ! -s "$OUT/manifest.json" ]; then rm -rf "$OUT"; fi' EXIT

COMPOSE="docker compose"
PROJECT="${COMPOSE_PROJECT_NAME:-$(backup_dotenv_get COMPOSE_PROJECT_NAME)}"
PROJECT="${PROJECT:-civora-host}"

if [ "$ENCRYPT" = "1" ]; then
  DB_FILE="db.dump.age"
  STORAGE_FILE="storage.tar.gz.age"
  echo "==> Encryption: age (public-key recipients only, no private key here)"
else
  DB_FILE="db.dump"
  STORAGE_FILE="storage.tar.gz"
  echo "WARNING: BACKUP_AGE_RECIPIENTS is not set: this backup is NOT encrypted." \
    "Not acceptable for real data (docs/ops/restore-runbook.md)."
fi

# Writes stdin to $1; encrypts on the way when enabled. pipefail makes a
# failing pg_dump or tar fail the whole step instead of leaving a short file.
store() {
  if [ "$ENCRYPT" = "1" ]; then
    backup_age_encrypt > "$1" || return 1
    # age output starts with its fixed header; an empty or error-only file would not.
    [ "$(head -c 21 "$1")" = "age-encryption.org/v1" ] || { echo "ERROR: $1 is not an age file"; return 1; }
  else
    cat > "$1"
  fi
}

echo "==> Postgres dump"
$COMPOSE exec -T db pg_dump -Fc -U postgres decidim_app_production | store "$OUT/$DB_FILE"

echo "==> Attachments (app-storage volume)"
docker run --rm -v "${PROJECT}_app-storage":/src:ro alpine \
  tar czf - -C /src . | store "$OUT/$STORAGE_FILE"

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

if [ "$ENCRYPT" = "1" ]; then ENCRYPTED_JSON=true; else ENCRYPTED_JSON=false; fi

# Checksums first: they cover the stored (encrypted) artifacts, and a restore
# verifies them before it decrypts anything.
(cd "$OUT" && shasum -a 256 "$DB_FILE" "$STORAGE_FILE" > sha256.txt)

{
  echo "{"
  echo "  \"timestamp\": \"$STAMP\","
  echo "  \"image_tag\": \"$IMAGE_TAG\","
  echo "  \"git_sha\": \"$GIT_SHA\","
  echo "  \"postgres_major\": 17,"
  echo "  \"encrypted\": $ENCRYPTED_JSON,"
  echo "  \"encryption\": \"$([ "$ENCRYPT" = "1" ] && echo age || echo none)\","
  echo "  \"files\": [\"$DB_FILE\", \"$STORAGE_FILE\"],"
  echo "  \"row_counts\": {"
  awk -F= 'NR>1 {printf ",\n"} {printf "    \"%s\": %s", $1, $2}' "$OUT/row_counts.txt"
  echo ""
  echo "  }"
  echo "}"
} > "$OUT/manifest.json"

# Dead-man ping (civora-org/civora-platform#51): report the last successful
# local backup to pushgateway; Prometheus alerts (BackupStale, >26h) when it
# goes stale. Deliberately non-fatal: a failed ping must NOT turn a good backup
# into a cron failure; the staleness alert covers the missed ping.
if [ -n "${PUSHGATEWAY_URL:-}" ]; then
  echo "==> Pushgateway dead-man ping"
  if backup_push_gauge civora_backup_last_success_unixtime "$(date -u +%s)"; then
    echo "    ping ok"
  else
    echo "    WARNING: pushgateway ping failed (backup itself succeeded)"
  fi
else
  echo "WARNING: PUSHGATEWAY_URL is not set: dead-man ping skipped;" \
    "the BackupStale alert will stay firing until it is armed" \
    "(docs/ops/observability.md)"
fi

echo "Backup written to $OUT"
cat "$OUT/manifest.json"

# Off-site copy. A failure here exits non-zero (cron mails it, the off-site
# staleness alert fires after 26 h), but the local backup above stands.
if backup_offsite_configured; then
  scripts/backup_offsite.sh "$OUT"
else
  echo "WARNING: BACKUP_OFFSITE_BUCKET is not set: this backup stays on this machine." \
    "Not acceptable before real data (docs/ops/restore-runbook.md)."
fi
