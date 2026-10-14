#!/bin/sh
# Decrypt a backup directory into plaintext files for a manual restore
# (civora-org/civora-platform#167). Run it on the operator's machine, where the
# age private key lives: never on the production server.
#
# Usage: BACKUP_AGE_IDENTITY_FILE=/path/to/key scripts/backup_decrypt.sh BACKUP_DIR OUT_DIR
#
# OUT_DIR (created 0700) receives db.dump and storage.tar.gz; copy manifest.json
# and sha256.txt along yourself if you need them. The plaintext is the same
# personal data the production database holds: delete OUT_DIR when the restore
# is done. A drill does not need this script (restore_drill.sh decrypts as a
# stream and writes no plaintext to disk).
set -eu

cd "$(dirname "$0")/.."

# shellcheck source=lib/backup_env.sh
. scripts/lib/backup_env.sh

IN="${1:-}"
OUT="${2:-}"
[ -n "$IN" ] && [ -n "$OUT" ] || { echo "usage: BACKUP_AGE_IDENTITY_FILE=... scripts/backup_decrypt.sh BACKUP_DIR OUT_DIR"; exit 2; }
[ -n "${BACKUP_AGE_IDENTITY_FILE:-}" ] || { echo "Set BACKUP_AGE_IDENTITY_FILE to the age private key file"; exit 2; }
[ -f "$IN/db.dump.age" ] && [ -f "$IN/storage.tar.gz.age" ] || { echo "$IN has no encrypted artifacts (db.dump.age, storage.tar.gz.age)"; exit 1; }

(cd "$IN" && shasum -a 256 -c sha256.txt)

umask 077
mkdir -p "$OUT"
chmod 700 "$OUT"
backup_age_decrypt "$BACKUP_AGE_IDENTITY_FILE" < "$IN/db.dump.age" > "$OUT/db.dump"
backup_age_decrypt "$BACKUP_AGE_IDENTITY_FILE" < "$IN/storage.tar.gz.age" > "$OUT/storage.tar.gz"
echo "Decrypted into $OUT (plaintext personal data: delete it after the restore)"
