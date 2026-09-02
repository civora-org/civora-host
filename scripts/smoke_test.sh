#!/usr/bin/env bash
# Docker smoke test (civora-org/civora-platform#48):
# clean state -> compose up -> healthy -> GET /contracts -> 200 -> teardown.
#
# --keep-up (or SMOKE_NO_TEARDOWN=1) leaves the stack running: deploy.sh
# uses this mode so its deep /healthz check (step 5) runs against the same
# stack the smoke test validated. Keep-up also skips the initial teardown —
# it must never `down -v` a freshly deployed stack's volumes.
set -euo pipefail

cd "$(dirname "$0")/.."

KEEP_UP=0
for arg in "$@"; do
  case "$arg" in
    --keep-up) KEEP_UP=1 ;;
    *) echo "usage: smoke_test.sh [--keep-up]"; exit 2 ;;
  esac
done
if [ "${SMOKE_NO_TEARDOWN:-0}" = "1" ]; then
  KEEP_UP=1
fi

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

BASE_URL="${BASE_URL:-http://localhost:3000}"

cleanup() {
  if [ "$KEEP_UP" = 1 ]; then
    echo "==> Keeping the stack up (no teardown requested)"
    return 0
  fi
  docker compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [ "$KEEP_UP" != 1 ]; then
  echo "==> Tearing down any existing stack (clean-machine simulation)"
  docker compose down -v --remove-orphans >/dev/null
fi

echo "==> Building and starting"
docker compose up -d --build

echo "==> Waiting for app health"
for i in $(seq 1 60); do
  status="$(docker inspect --format '{{.State.Health.Status}}' "$(docker compose ps -q app)")"
  [ "$status" = "healthy" ] && break
  [ "$i" = 60 ] && { echo "app never became healthy (last: $status)"; docker compose logs --tail 100 app; exit 1; }
  sleep 5
done
echo "    healthy"

code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE_URL/contracts")"
echo "==> GET /contracts -> $code"
[ "$code" = "200" ] || { echo "FAIL: expected 200"; exit 1; }

echo "PASS: clean machine serves /contracts with 200"
