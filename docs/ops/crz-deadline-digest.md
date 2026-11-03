# CRZ deadline digest

The contracts engine (`decidim-contracts_sk` v1.10.0) sends a morning email to an organisation's admins and editors listing the contracts whose CRZ publication deadline is close or missed. The engine ships the rake task `decidim_contracts_sk:crz_deadline_digest[<organization_id>]` (omit the id for all organisations; output is counts only). The host decides when it runs (civora-org/civora-platform#211).

## How it runs

The `digest-scheduler` service in `compose.yaml` reuses the `civora-host:latest` image (same env, database and Redis wiring as `app`, no ports) and loops `scripts/crz_deadline_digest_scheduler.sh`: sleep until the next **07:30 `Europe/Bratislava` on Monday to Friday**, run the task for every organisation, repeat. Public holidays are not excluded; a digest on a holiday is harmless. A failing run is logged and never ends the loop. It has no state, so there is no catch-up: a run missed while the container was down is not repeated.

It sends real email, so it needs working SMTP (`SMTP_*` in `.env`, see `.env.example`). Without SMTP the run fails and the log says so; nothing else breaks.

The demo compose overlay puts the service in the `crz-sync` profile, so the demo never starts it (it has no real CRZ deadlines).

## Operations

```bash
docker compose up -d digest-scheduler                    # start (waits for db/redis)
docker compose logs -f digest-scheduler                  # next-run time, per-run counts
docker compose exec digest-scheduler bin/rails "decidim_contracts_sk:crz_deadline_digest[1]"   # one organisation now
```

After the first deploy, send one digest by hand to confirm SMTP and recipients instead of waiting for 07:30.

## Test hooks

| Var | Default | Purpose |
| --- | --- | --- |
| `CRZ_DIGEST_RUN_AT` | `07:30` | Time of day (HH:MM, `Europe/Bratislava`) of the run |
| `CRZ_DIGEST_ONESHOT` | unset | `1` runs once immediately and exits |
