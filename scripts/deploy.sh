#!/bin/sh
# Production deploy: backup-gated rebuild of the compose stack.
#
# Order (required by docs/05-operations/civora-ci-cd-plan.md, "Backup completed"):
#   backup -> manifest verify -> docker compose up -d --build -> smoke test
#   -> monitoring review
# Aborts if the backup or its verification fails — never deploy unbacked-up.
set -eu

cd "$(dirname "$0")/.."

# Compose file selection in one place: defer to COMPOSE_FILE pinned in .env
# when present; otherwise include the observability overlay when it exists,
# base compose.yaml when it does not (dev machines without the file).
if ! grep -q '^COMPOSE_FILE=' .env 2>/dev/null; then
  if [ -f compose.observability.yml ]; then
    COMPOSE_FILE=compose.yaml:compose.observability.yml
  else
    COMPOSE_FILE=compose.yaml
  fi
  export COMPOSE_FILE
fi

# shellcheck source=lib/stack_url.sh
. scripts/lib/stack_url.sh
BASE_URL="$(stack_base_url)"

# Container env for `docker compose up` (release provenance for Sentry/
# GlitchTip via config/initializers/sentry.rb).
GIT_REVISION="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "==> 1/5 Backup (pre-deploy gate)"
scripts/backup.sh
LATEST="$(ls -d backups/*/ | sort | tail -1)"
echo "Backup at: $LATEST"

echo "==> 2/5 Verify backup artifacts"
(cd "$LATEST" && shasum -a 256 -c sha256.txt)
# Encrypted backups (civora-org/civora-platform#167) store db.dump.age and
# storage.tar.gz.age; plaintext ones db.dump and storage.tar.gz.
if [ -s "$LATEST/db.dump.age" ]; then
  ARTIFACTS="db.dump.age storage.tar.gz.age manifest.json"
else
  ARTIFACTS="db.dump storage.tar.gz manifest.json"
fi
for f in $ARTIFACTS; do
  [ -s "$LATEST/$f" ] || { echo "MISSING: $f — aborting deploy"; exit 1; }
done

echo "==> 3/5 Rebuild and start stack"
GITHUB_TOKEN="$(grep '^GITHUB_TOKEN=' .env | cut -d= -f2-)" \
  GIT_REVISION="$GIT_REVISION" \
  docker compose up -d --build

echo "==> 4/5 Smoke test"
if [ -x scripts/smoke_test.sh ]; then
  # --keep-up: the stack must survive the smoke test — step 5 below checks
  # /healthz against it, and `down -v` must never run mid-deploy.
  GITHUB_TOKEN="$(grep '^GITHUB_TOKEN=' .env | cut -d= -f2-)" \
    GIT_REVISION="$GIT_REVISION" \
    scripts/smoke_test.sh --keep-up
else
  for i in $(seq 1 30); do
    code="$(stack_curl -sL -o /dev/null -w '%{http_code}' "$BASE_URL/contracts" || true)"
    [ "$code" = "200" ] && break
    sleep 2
  done
  [ "$code" = "200" ] || { echo "Smoke check failed (last: $code)"; exit 1; }
fi

echo "==> 5/5 Monitoring review"
# Deep health: unlike the smoke test, /healthz verifies database AND Redis.
code="$(stack_curl -sL -o /dev/null -w '%{http_code}' "$BASE_URL/healthz" || true)"
if [ "$code" != "200" ]; then
  echo "Deep health check failed (/healthz -> ${code:-no response}) — aborting deploy"
  exit 1
fi
echo "    deep health ok (database + redis reachable)"
echo "    Review monitoring before sign-off (see docs/ops/observability.md):"
echo "      - Prometheus targets green:  http://127.0.0.1:9090/targets"
echo "      - No firing alerts:          http://127.0.0.1:9090/alerts"
echo "      - Errors reported to GlitchTip: http://127.0.0.1:8080"

echo "Deploy complete."
