#!/bin/sh
# Morning CRZ deadline digest loop for the `digest-scheduler` compose service
# (civora-org/civora-platform#211 ships the engine task, decidim-contracts_sk
# v1.10.0): sleep until the next working day at 07:30 Europe/Bratislava, run
# `decidim_contracts_sk:crz_deadline_digest` for every organization, repeat.
# "Working day" here is Monday to Friday; public holidays are not excluded
# (a digest on a holiday is harmless). 07:30 exists on both DST switch nights.
# Runs inside the app image (tzdata is installed there); TZ is set by compose.
# A failing run (for example SMTP down) is logged and never ends the loop.
# The task prints counts only. CRZ_DIGEST_RUN_AT (HH:MM, default 07:30) and
# CRZ_DIGEST_ONESHOT=1 (run once immediately, then exit) exist for testing.
set -u

cd "$(dirname "$0")/.."
export TZ="${TZ:-Europe/Bratislava}"
RUN_AT="${CRZ_DIGEST_RUN_AT:-07:30}"

log() { echo "[crz-digest-scheduler] $(date +%Y-%m-%dT%H:%M:%S%z) $*"; }

run_digest() {
  log "running decidim_contracts_sk:crz_deadline_digest"
  bin/rails decidim_contracts_sk:crz_deadline_digest
}

if [ "${CRZ_DIGEST_ONESHOT:-0}" = "1" ]; then
  run_digest
  exit $?
fi

# Epoch seconds of the next RUN_AT that lies in the future on Monday..Friday.
next_run() {
  now="$(date +%s)"
  offset=0
  while [ "$offset" -le 7 ]; do
    candidate="$(date -d "today + $offset days $RUN_AT" +%s 2>/dev/null)" || return 1
    weekday="$(date -d "@$candidate" +%u)"
    if [ "$candidate" -gt "$now" ] && [ "$weekday" -le 5 ]; then
      echo "$candidate"
      return 0
    fi
    offset=$((offset + 1))
  done
  return 1
}

while true; do
  now="$(date +%s)"
  next="$(next_run)" || next=""
  if [ -z "$next" ]; then
    log "ERROR: cannot compute next run time for RUN_AT=$RUN_AT; retrying in 1h"
    sleep 3600
    continue
  fi
  wait_s=$((next - now))
  [ "$wait_s" -ge 60 ] || wait_s=60
  log "next run at $(date -d "@$next" +%Y-%m-%dT%H:%M:%S%z) (in ${wait_s}s)"
  sleep "$wait_s"
  run_digest || log "digest run failed (see log above)"
done
