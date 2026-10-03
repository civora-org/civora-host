#!/bin/sh
# Nightly CRZ sync loop for the `scheduler` compose service
# (civora-org/civora-platform#138): sleep until the next 03:30
# Europe/Bratislava, run one pass (scripts/crz_sync_run.sh), repeat.
# 03:30 (not 02:30) because 02:30 does not exist on the spring-forward night.
# Runs inside the app image (tzdata is installed there); TZ is set by compose.
# A failing or locked-out pass is logged and never ends the loop.
# CRZ_SYNC_RUN_AT (HH:MM, default 03:30) and CRZ_SYNC_ONESHOT=1 (run one pass
# immediately, then exit) exist for testing.
set -u

cd "$(dirname "$0")/.."
export TZ="${TZ:-Europe/Bratislava}"
RUN_AT="${CRZ_SYNC_RUN_AT:-03:30}"

log() { echo "[crz-sync-scheduler] $(date +%Y-%m-%dT%H:%M:%S%z) $*"; }

if [ "${CRZ_SYNC_ONESHOT:-0}" = "1" ]; then
  sh scripts/crz_sync_run.sh
  exit $?
fi

while true; do
  now="$(date +%s)"
  next="$(date -d "today $RUN_AT" +%s 2>/dev/null)" || next=""
  if [ -n "$next" ] && [ "$next" -le "$now" ]; then
    next="$(date -d "tomorrow $RUN_AT" +%s 2>/dev/null)" || next=""
  fi
  if [ -z "$next" ]; then
    log "ERROR: cannot compute next run time for RUN_AT=$RUN_AT; retrying in 1h"
    sleep 3600
    continue
  fi
  wait_s=$((next - now))
  [ "$wait_s" -ge 60 ] || wait_s=60
  log "next run at $(date -d "@$next" +%Y-%m-%dT%H:%M:%S%z) (in ${wait_s}s)"
  sleep "$wait_s"
  sh scripts/crz_sync_run.sh || log "pass finished with failures or was skipped (see log above)"
done
