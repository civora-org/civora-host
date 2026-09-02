# Observability

How the self-hosted observability stack fits together (civora-org/civora-platform#51): error tracking, metrics, alerting, and the backup dead-man switch. Nothing leaves the machine — GlitchTip replaces Sentry's SaaS, Prometheus + Alertmanager replace a hosted metrics/alerting product.

## Services and ports

The stack is driven by `COMPOSE_FILE` (docker compose reads it from `.env`), so one plain `docker compose` command always targets the right files — the overlay when pinned, base-only otherwise:

```bash
# one-time: add the overlay to .env
echo 'COMPOSE_FILE=compose.yaml:compose.observability.yml' >> .env

docker compose up -d
```

Omitting the overlay (no `COMPOSE_FILE` in `.env`) runs the base stack only; `scripts/deploy.sh` and `scripts/smoke_test.sh` default to the overlay whenever `compose.observability.yml` exists and `.env` does not pin `COMPOSE_FILE`.

| Service               | Image                          | Published (127.0.0.1) | Purpose |
| --------------------- | ------------------------------ | --------------------- | ------- |
| `glitchtip`           | `glitchtip/glitchtip:v5`       | 8080                  | Sentry-protocol error tracking (UI + ingestion) |
| `glitchtip-worker`    | `glitchtip/glitchtip:v5`       | —                     | GlitchTip background event processing |
| `glitchtip-db`        | `postgres:16-alpine`           | —                     | GlitchTip's own database |
| `prometheus`          | `prom/prometheus:v3.7.3`       | 9090                  | Scrapes and stores metrics, evaluates alert rules |
| `alertmanager`        | `prom/alertmanager:v0.28.1`    | 9093                  | Routes firing alerts to a webhook |
| `blackbox-exporter`   | `prom/blackbox-exporter:v0.27.0` | —                   | Synthetic HTTP probes of `/up` and `/healthz` |
| `prometheus-exporter` | `civora-host:latest`           | —                     | Collector the Rails middleware pushes metrics to (9394, internal) |
| `pushgateway`         | `prom/pushgateway:v1.11.0`     | 9091                  | Backup dead-man ping target (host cron pushes from outside the network) |

All published ports are bound to `127.0.0.1` — sufficient for local testing and for a future same-host reverse proxy; nothing is exposed to other machines.

## Required / optional env vars

Add to `.env` (never commit it; template in `.env.example`):

| Var                     | Required | Purpose |
| ----------------------- | -------- | ------- |
| `GLITCHTIP_SECRET_KEY`  | yes      | Secret key for the GlitchTip services (`openssl rand -hex 64`) |
| `GLITCHTIP_DB_PASSWORD` | yes      | Password for the GlitchTip Postgres database (`openssl rand -hex 16`) |
| `GLITCHTIP_DOMAIN`      | no       | Public base URL of GlitchTip (default `http://localhost:8080`) |
| `SENTRY_DSN`            | no       | App error reporting; a GlitchTip project DSN. Sentry is disabled when unset |
| `PUSHGATEWAY_URL`      | no       | Backup dead-man ping target, e.g. `http://127.0.0.1:9091` (used by `scripts/backup.sh`, which also reads it from `.env` directly — so host cron picks it up without sourcing) |
| `ALERT_WEBHOOK_URL`     | no       | Where Alertmanager delivers alerts; falls back to a logging blackhole when unset |

`PROMETHEUS_EXPORTER_HOST`/`PROMETHEUS_EXPORTER_PORT` are set by the overlay for the `app` service — do not put them in `.env`.

## GlitchTip first boot

1. Open `http://127.0.0.1:8080`, create an account, then a project.
2. Copy the project's **DSN** and set it as `SENTRY_DSN` in `.env`, then recreate the app: `docker compose up -d app`.
3. `config/initializers/sentry.rb` initialises the SDK only when `SENTRY_DSN` is set, with privacy hardening (`send_default_pii = false`, request data and user stripped via `before_send`).

## How the metrics flow

```
Rails app ──(PrometheusExporter::Middleware, per-request push)──▶ prometheus-exporter:9394
blackbox-exporter ◀──(scrape /probe)── Prometheus ◀──(scrape /metrics)── prometheus-exporter:9394
blackbox-exporter ──(HTTP GET http://app:3000/up and /healthz)──▶ Rails app
scripts/backup.sh ──(push civora_backup_last_success_unixtime)──▶ pushgateway:9091
```

- The middleware (`config/initializers/prometheus_exporter.rb`) activates only when `PROMETHEUS_EXPORTER_HOST` is set — development and tests are unaffected.
- Prometheus config: `observability/prometheus/prometheus.yml` (scrape jobs, 30s interval); alert rules: `observability/prometheus/rules.yml`; probe modules: `observability/blackbox/blackbox.yml`.
- Request metrics carry the prometheus_exporter default `ruby_` prefix (e.g. `ruby_http_requests_total{status="500"}`).

## Alerts

Rules in `observability/prometheus/rules.yml` implement the CI/CD plan thresholds (civora-platform `docs/05-operations/civora-ci-cd-plan.md`):

| Alert                    | Severity | Condition |
| ------------------------ | -------- | --------- |
| `AppUptimeCritical`      | critical | uptime < 95% over 5m (blackbox `/up` probe) |
| `HttpErrorRateCritical`  | critical | 5xx rate > 5% over 5m |
| `AppUptimeHigh`          | high     | uptime < 99% over 1h |
| `HttpErrorRateHigh`      | high     | 5xx rate > 1% over 1h |
| `BackupStale`            | high     | backup ping stale > 26h or never pushed (cron: nightly 03:15 `Europe/Bratislava`) |
| `DeepHealthCheckFailing` | warning  | `/healthz` probe failing (db/redis down while `/up` may still pass) |

Routing (`observability/alertmanager/alertmanager.yml`): all severities go to the `alert-webhook` receiver whose URL comes from `ALERT_WEBHOOK_URL`. Alertmanager config files cannot read env vars, so `compose.observability.yml` substitutes the placeholder with `sed` at container start. **Fallback:** with `ALERT_WEBHOOK_URL` unset, the URL is a localhost blackhole — delivery attempts fail and are logged, and alerts stay visible in the Alertmanager UI (`http://127.0.0.1:9093`); that is the documented "log" fallback until a real receiver (e.g. a Slack/Mattermost bridge) is configured.

## Synthetic-failure tests (issue #51 verification)

Run the stack, wait for Prometheus to pick up targets (`http://127.0.0.1:9090/targets` — all green), then:

1. **Uptime critical:** `docker compose stop app`. Within ≤5m Prometheus evaluates `probe_success{job="blackbox-up"} == 0`; after the rule's `for: 2m`, `AppUptimeCritical` fires (`http://127.0.0.1:9090/alerts`). Start the app again; the alert resolves.
2. **Deep health warning:** `docker compose stop db`. `/healthz` returns 503 and `DeepHealthCheckFailing` fires (warning). Restart `db`.
3. **Error rate critical:** with `db` stopped, request real pages (`curl http://127.0.0.1:3000/contracts` style, or any route hitting the DB) — Rails renders 500s, pushing `ruby_http_requests_total{status="5.."}`; `HttpErrorRateCritical` fires once 5xx > 5% over 5m. Inspect raw series under `http://127.0.0.1:9090/graph`.
4. **Backup dead-man:** simulate a stale backup by pushing an old timestamp:
   ```bash
   printf 'civora_backup_last_success_unixtime 1000000000\n' | \
     curl --data-binary @- http://127.0.0.1:9091/metrics/job/civora-backup
   ```
   `BackupStale` fires (~10m, the rule's `for`). The `absent()` branch can be tested on a fresh pushgateway (no push yet). Then verify the real path: `PUSHGATEWAY_URL=http://127.0.0.1:9091 scripts/backup.sh` and confirm the metric at `http://127.0.0.1:9091` shows the current time.
5. **Error tracking:** `docker compose exec app bin/rails runner 'Sentry.capture_message("synthetic test event (civora-org/civora-platform#51)")'` — the event appears in the GlitchTip project within seconds.
6. **Alert delivery:** set `ALERT_WEBHOOK_URL` to a listener (e.g. `nc -l 8081` or a webhook.site-style local receiver), trigger any alert, and confirm the POST arrives; `send_resolved: true` means you also get the resolution payload.
