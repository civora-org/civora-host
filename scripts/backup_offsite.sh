#!/bin/sh
# Copy one finished backup directory to the off-site S3-compatible target and
# verify it arrived (civora-org/civora-platform#167).
#
# Usage: scripts/backup_offsite.sh BACKUP_DIR      (normally called by backup.sh)
#
# Target (env or .env, see scripts/lib/backup_env.sh): BACKUP_OFFSITE_BUCKET,
# _PREFIX, _ENDPOINT, _REGION, _PROVIDER, _ACCESS_KEY_ID, _SECRET_ACCESS_KEY.
# The copy goes to <bucket>/<prefix>/<timestamp>/. It refuses to upload a
# backup that is not encrypted when BACKUP_STRICT=1. Order: the encrypted
# artifacts first, then sha256.txt and manifest.json, so a directory without a
# manifest on the remote is an interrupted upload and is never used by a restore.
#
# After the upload the files are compared with the local copy by size and
# checksum (rclone check); only then the off-site dead-man gauge
# civora_backup_offsite_last_success_unixtime is pushed. A failed upload exits
# non-zero and pushes nothing, so the OffsiteBackupStale alert fires.
set -eu

cd "$(dirname "$0")/.."

# shellcheck source=lib/backup_env.sh
. scripts/lib/backup_env.sh
backup_env_load

DIR="${1:-}"
[ -n "$DIR" ] && [ -s "$DIR/manifest.json" ] || { echo "usage: scripts/backup_offsite.sh BACKUP_DIR (a finished backup with manifest.json)"; exit 2; }
backup_offsite_configured || { echo "BACKUP_OFFSITE_BUCKET is not set"; exit 2; }
[ -n "${BACKUP_OFFSITE_ACCESS_KEY_ID:-}" ] && [ -n "${BACKUP_OFFSITE_SECRET_ACCESS_KEY:-}" ] \
  || { echo "BACKUP_OFFSITE_ACCESS_KEY_ID / BACKUP_OFFSITE_SECRET_ACCESS_KEY are not set"; exit 2; }

if [ "${BACKUP_STRICT:-0}" = "1" ] && [ ! -f "$DIR/db.dump.age" ]; then
  echo "ERROR: BACKUP_STRICT=1 and $DIR is not encrypted: refusing to upload plaintext"
  exit 1
fi
if [ ! -f "$DIR/db.dump.age" ]; then
  echo "WARNING: uploading an UNENCRYPTED backup off-site"
fi

stamp="$(basename "$DIR")"
remote="$(backup_remote_base)/$stamp"

echo "==> Off-site copy to ${remote} (artifacts first, manifest last)"
backup_rclone_local ro "$DIR" copy @LOCAL@ "$remote" \
  --exclude manifest.json --exclude sha256.txt --exclude row_counts.txt --checksum
backup_rclone_local ro "$DIR" copy @LOCAL@ "$remote" \
  --include manifest.json --include sha256.txt --include row_counts.txt --checksum

echo "==> Verify off-site copy against the local one"
backup_rclone_local ro "$DIR" check @LOCAL@ "$remote" --one-way

echo "==> Off-site dead-man ping"
if backup_push_gauge civora_backup_offsite_last_success_unixtime "$(date -u +%s)"; then
  echo "    ping ok"
else
  echo "    WARNING: pushgateway ping failed or PUSHGATEWAY_URL unset (upload itself succeeded)"
fi
echo "Off-site copy verified: $remote"
