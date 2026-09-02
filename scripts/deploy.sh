#!/bin/sh
# Production deploy: backup-gated rebuild of the compose stack.
#
# Order (required by docs/05-operations/civora-ci-cd-plan.md, "Backup completed"):
#   backup -> manifest verify -> docker compose up -d --build -> smoke test
# Aborts if the backup or its verification fails — never deploy unbacked-up.
set -eu

cd "$(dirname "$0")/.."

echo "==> 1/4 Backup (pre-deploy gate)"
scripts/backup.sh
LATEST="$(ls -d backups/*/ | sort | tail -1)"
echo "Backup at: $LATEST"

echo "==> 2/4 Verify backup artifacts"
(cd "$LATEST" && shasum -a 256 -c sha256.txt)
for f in db.dump storage.tar.gz manifest.json; do
  [ -s "$LATEST/$f" ] || { echo "MISSING: $f — aborting deploy"; exit 1; }
done

echo "==> 3/4 Rebuild and start stack"
GITHUB_TOKEN="$(grep '^GITHUB_TOKEN=' .env | cut -d= -f2-)" \
  docker compose up -d --build

echo "==> 4/4 Smoke test"
if [ -x scripts/smoke_test.sh ]; then
  GITHUB_TOKEN="$(grep '^GITHUB_TOKEN=' .env | cut -d= -f2-)" scripts/smoke_test.sh
else
  for i in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/contracts || true)"
    [ "$code" = "200" ] && break
    sleep 2
  done
  [ "$code" = "200" ] || { echo "Smoke check failed (last: $code)"; exit 1; }
fi

echo "Deploy complete."
