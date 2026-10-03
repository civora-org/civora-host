#!/bin/sh
# One CRZ sync pass over every organization (civora-org/civora-platform#138).
#
# Runs INSIDE the app image (the `scheduler` compose service calls it nightly
# via scripts/crz_sync_scheduler.sh); also the entry point for manual re-runs:
#   docker compose exec scheduler sh scripts/crz_sync_run.sh
#
# Per organization: SINCE = last successful run's START time minus 1 day
# (overlap is safe, the engine sync is idempotent). With no state yet:
# CRZ_SYNC_INITIAL_SINCE (ISO8601, global for all organizations) or 7 days
# ago; that first-attempt seed is persisted per organization (org-<id>.seed)
# and reused until the first success, so retries do not drift. On exit 0 the run's start
# time is stored and pushed to pushgateway as
# civora_crz_sync_last_success_unixtime; on failure only
# civora_crz_sync_last_run_success=0 is pushed (POST replaces by metric name,
# so the stored success timestamp survives). One failing organization never
# stops the others; the script exits 1 if any failed. A flock on the state
# directory prevents overlapping passes (manual run vs. the nightly one).
#
# Env: CRZ_SYNC_STATE_DIR (default /app/tmp/crz-sync), CRZ_SYNC_INITIAL_SINCE,
# CRZ_SYNC_PUSHGATEWAY_URL (default http://pushgateway:9091), ACTOR_EMAIL
# (passed through to the rake task). Logs ids and counts only, never payloads.
set -u

cd "$(dirname "$0")/.."

STATE_DIR="${CRZ_SYNC_STATE_DIR:-/app/tmp/crz-sync}"
PUSHGATEWAY="${CRZ_SYNC_PUSHGATEWAY_URL:-http://pushgateway:9091}"
mkdir -p "$STATE_DIR"

exec 9>"$STATE_DIR/.lock"
flock -n 9 || { echo "[crz-sync] another sync pass holds the lock; exiting"; exit 1; }

log() { echo "[crz-sync] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

# Non-fatal push: pushgateway trouble must not fail the sync itself; the
# CrzSyncStale alert covers a missed ping.
push() { # $1 org id, $2 metrics body
  PUSH_URL="$PUSHGATEWAY/metrics/job/civora-crz-sync/organization/$1" \
  PUSH_BODY="$2" ruby -rnet/http -ruri -e '
    begin
      uri = URI(ENV.fetch("PUSH_URL"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = http.read_timeout = 10
      res = http.post(uri.path, ENV.fetch("PUSH_BODY"), "Content-Type" => "text/plain")
      exit(res.code.to_i.between?(200, 299) ? 0 : 1)
    rescue StandardError => e
      warn "[crz-sync] push error: #{e.class}"
      exit 1
    end
  ' || log "WARNING: pushgateway push failed for organization $1 (sync result unaffected)"
}

org_ids="$(bin/rails runner 'puts Decidim::Organization.order(:id).pluck(:id)' | grep -E '^[0-9]+$')" || org_ids=""
if [ -z "$org_ids" ]; then
  log "ERROR: no organizations found (or the rails runner failed)"
  exit 1
fi

failed=0
for org in $org_ids; do
  started="$(date -u +%s)"
  state_file="$STATE_DIR/org-$org"
  seed_file="$STATE_DIR/org-$org.seed"
  last=""
  if [ -f "$state_file" ]; then
    last="$(head -n 1 "$state_file" | tr -d '[:space:]')"
    case "$last" in
      ''|*[!0-9]*)
        log "WARNING: state file for organization $org is corrupt or empty; treating as no state"
        last="" ;;
    esac
  fi

  if [ -n "$last" ]; then
    since="$(date -u -d "@$((last - 86400))" +%Y-%m-%dT%H:%M:%SZ)"
  elif [ -s "$seed_file" ]; then
    since="$(head -n 1 "$seed_file")"
  else
    if [ -n "${CRZ_SYNC_INITIAL_SINCE:-}" ]; then
      since="$CRZ_SYNC_INITIAL_SINCE"
    else
      since="$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)"
    fi
    printf '%s\n' "$since" > "$seed_file"
  fi

  log "organization $org: start, since=$since"
  if SINCE="$since" bin/rails "decidim_contracts_sk:crz_import:sync[$org]"; then
    printf '%s\n' "$started" > "$state_file"
    rm -f "$seed_file"
    log "organization $org: success"
    push "$org" "civora_crz_sync_last_success_unixtime $started
civora_crz_sync_last_run_success 1
"
  else
    code=$?
    failed=1
    log "organization $org: FAILED (exit $code); success cursor unchanged"
    push "$org" "civora_crz_sync_last_run_success 0
"
  fi
done

[ "$failed" -eq 0 ] || exit 1
log "pass complete"
