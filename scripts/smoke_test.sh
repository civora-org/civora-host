#!/usr/bin/env bash
# Docker smoke test (civora-org/civora-platform#48):
# clean state -> compose up -> healthy -> GET /contracts -> 200 -> teardown.
set -euo pipefail

cd "$(dirname "$0")/.."

BASE_URL="${BASE_URL:-http://localhost:3000}"

cleanup() {
  docker compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Tearing down any existing stack (clean-machine simulation)"
docker compose down -v --remove-orphans >/dev/null

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
