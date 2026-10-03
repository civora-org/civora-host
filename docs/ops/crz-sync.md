# CRZ sync scheduler

Nightly import of CRZ contract mirrors into every organization (civora-org/civora-platform#138, engine side: ADR-008 and the engine's `docs/crz-import.md`). Alerting: `CrzSyncStale` (`docs/ops/observability.md`).

## How it runs

The `scheduler` service in `compose.yaml` reuses the `civora-host:latest` image (same env, database and Redis wiring as `app`, no ports) and loops `scripts/crz_sync_scheduler.sh`: sleep until the next **03:30 `Europe/Bratislava`** (not 02:30: that wall-clock time does not exist on the spring-forward night; it also runs after the 03:15 backup), run one pass of `scripts/crz_sync_run.sh`, repeat. A failing or lock-skipped pass never ends the loop; the pass holds a `flock` on the state directory, so a manual run overlapping the nightly one exits 1 instead of racing it.

Each pass lists the organization ids and, per organization, runs `bin/rails "decidim_contracts_sk:crz_import:sync[<org>,<since>]"`:

- `since` = start time of the last successful run minus 1 day (the overlap is safe, the sync is idempotent). Without state: `CRZ_SYNC_INITIAL_SINCE` (global, applies to every organization without a cursor), else 7 days ago. That first-attempt seed is persisted as `<state>/org-<id>.seed` and reused until the first success, so retries do not drift; delete the `.seed` file to change it. A corrupt or empty state file is logged as a warning and treated as no state.
- Exit 0: the run's **start** time is stored in `<state>/org-<id>` and `civora_crz_sync_last_success_unixtime` is pushed. Non-zero exit: logged, `civora_crz_sync_last_run_success 0` is pushed, the cursor is untouched. One failing organization does not stop the others; the pass exits 1 if any failed.
- Logs carry ids and counts only, never payloads.

### Why a compose service, not a systemd timer

The stack already lives in compose and the host runs no other scheduler: a service reuses the exact image, env and network (db, redis, pushgateway by service name), ships in the same `docker compose up`, needs no host-level unit files and has log caps and restart policy like every other service. The one cost is a sleeping container; cron/systemd would need `docker compose exec`/`run` wrappers and host config outside the repo.

### Files and state

- `.dockerignore` keeps `/scripts` out of the image, so `./scripts` is bind-mounted read-only at `/app/scripts` (same pattern as the observability configs). Script edits take effect at the next pass; restart `scheduler` to reload the loop script itself.
- The `crz-sync-state` volume is mounted at `/app/tmp` (rails-owned in the image, so a fresh volume gets the right ownership); state lives in `/app/tmp/crz-sync/org-<id>`. Wiping the volume re-runs from `CRZ_SYNC_INITIAL_SINCE`/7 days ago.

## Operations

```bash
docker compose up -d scheduler                    # start (waits for db/redis)
docker compose logs -f scheduler                  # next-run time, per-org results
docker compose exec scheduler sh scripts/crz_sync_run.sh   # manual pass now
docker compose exec -e CRZ_SYNC_INITIAL_SINCE=2026-09-01T00:00:00Z scheduler \
  sh scripts/crz_sync_run.sh                      # manual pass, first-run window
docker compose exec scheduler cat /app/tmp/crz-sync/org-1   # last success (unix s)
```

The manual pass uses the same cursor and pushes the same metrics. A first run with a wide window against the CRZ backlog is large (thousands of records) and can hit the ekosystem rate window (60 requests); the run then stops early and exits non-zero, with pages already applied kept. A rerun restarts from the same `since` (the sync does not resume from its pagination cursor; resume is a possible follow-up), so it can hit the same limit again: start with a narrow `CRZ_SYNC_INITIAL_SINCE` (for example 1 day ago) and widen it step by step, deleting the `.seed` file between steps while no success is recorded.

**After the first deploy, run one manual pass** (`docker compose exec scheduler sh scripts/crz_sync_run.sh`) to confirm the actor, source access and pushgateway wiring instead of waiting for 03:30.

### Reading logs and exit codes

Lines prefixed `[crz-sync]` come from the runner; the rake task prints `created/updated/unchanged`, `collisions/quarantined/failed/skipped` counts and ids. Rake exit 1 means either an early stop (`sync stopped early: ... TransportError`, source unreachable or throttled after retries) or an abort with a message: `No import actor for organization #N` (an admin with accepted admin terms must exist, or set `ACTOR_EMAIL`), invalid `SINCE`, unknown organization. Prior catalogue data is never degraded by a failed run.

### Resetting the cursor

```bash
docker compose exec scheduler sh -c 'rm /app/tmp/crz-sync/org-1'   # one organization
docker compose exec scheduler sh -c 'echo 1790000000 > /app/tmp/crz-sync/org-1'  # set to a unix time (since = that minus 1 day)
```

### Collisions and quarantine

Collisions (a CRZ record matching an existing manually authored contract) are never overwritten and need a human decision; quarantined records are malformed source rows, skipped and counted. See the engine's `docs/crz-import.md` for the resolution procedure.

### Alerting

`CrzSyncStale` fires per organization when the success timestamp is older than 54h (two missed nights plus slack), or globally when none was ever pushed. Pushgateway keeps metrics for removed organizations, which then alert forever; delete the group: `curl -X DELETE http://127.0.0.1:9091/metrics/job/civora-crz-sync/organization/<id>`. `CrzSyncNeverSucceeded` (warning, after 1h) covers an organization that has never succeeded (for example no admin with accepted terms), which has no timestamp series for `CrzSyncStale` to see.

## Environment variables

| Var | Default | Purpose |
| --- | --- | --- |
| `CRZ_SYNC_INITIAL_SINCE` | 7 days ago | ISO8601 cursor seed, global: applies to every organization without state |
| `CRZ_SYNC_PUSHGATEWAY_URL` | `http://pushgateway:9091` | Dead-man push target; failures are non-fatal |
| `ACTOR_EMAIL` | first admin with accepted terms | Login email of the audit/authorship user (read by the rake task; set it in `.env`) |
| `CRZ_SYNC_STATE_DIR` | `/app/tmp/crz-sync` | State directory (set by compose) |
| `CRZ_SYNC_RUN_AT` / `CRZ_SYNC_ONESHOT` | `03:30` / unset | Test hooks for the scheduler loop |
