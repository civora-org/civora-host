#!/bin/sh
# Download a backup from the off-site target into a local directory
# (civora-org/civora-platform#167). The files stay ENCRYPTED; decrypting needs
# the age private key (scripts/backup_decrypt.sh, or restore_drill.sh which
# decrypts as a stream).
#
# Usage: scripts/backup_fetch.sh [STAMP|latest] [DEST]
#   STAMP   a backup name like 20261014T031500Z; default latest
#   DEST    parent directory (default ./backups); the backup lands in DEST/STAMP
#
# "latest" is the newest remote backup that has a manifest.json (a directory
# without one is an interrupted upload). The sha256 of every file is checked
# after the download. Prints the resulting directory on the last line.
set -eu

cd "$(dirname "$0")/.."

# shellcheck source=lib/backup_env.sh
. scripts/lib/backup_env.sh
backup_env_load

WANT="${1:-latest}"
DEST="${2:-backups}"
backup_offsite_configured || { echo "BACKUP_OFFSITE_BUCKET is not set" >&2; exit 2; }

remote="$(backup_remote_base)"
if [ "$WANT" = "latest" ]; then
  WANT="$(backup_rclone lsf -R --include manifest.json "$remote" | sed 's|/manifest.json$||' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort | tail -1 || true)"
  [ -n "$WANT" ] || { echo "No complete backup found under $remote" >&2; exit 1; }
fi
case "$WANT" in
  ????????T??????Z) ;;
  *) echo "Not a backup name: $WANT" >&2; exit 2 ;;
esac

mkdir -p "$DEST"
chmod 700 "$DEST"
OUT="$DEST/$WANT"
mkdir -p "$OUT"
chmod 700 "$OUT"

echo "==> Download $remote/$WANT" >&2
backup_rclone_local rw "$OUT" copy "$remote/$WANT" @LOCAL@ --checksum >&2
[ -s "$OUT/manifest.json" ] && [ -s "$OUT/sha256.txt" ] || { echo "Incomplete backup: manifest.json or sha256.txt missing in $OUT" >&2; exit 1; }

echo "==> Verify checksums" >&2
(cd "$OUT" && shasum -a 256 -c sha256.txt) >&2 || { echo "Checksum mismatch: do not restore from this copy" >&2; exit 1; }

printf '%s\n' "$OUT"
