# Log policy

Where Civora host app logs live, how they rotate, and what may never end up in them.

## Application logs → stdout → Docker json-file

The Rails app logs to stdout (`RAILS_LOG_TO_STDOUT` is set in the container; `config/environments/production.rb` then installs a `$stdout` logger tagged with `request_id`). Docker captures stdout/stderr of each service with the `json-file` driver, capped by rotation settings in `compose.yaml` so logs cannot fill the host disk:

| Service  | max-size | max-file | Worst case |
| -------- | -------- | -------- | ---------- |
| `app`    | 10m      | 5        | 50 MB      |
| `db`     | 10m      | 3        | 30 MB      |
| `redis`  | 10m      | 3        | 30 MB      |

The observability overlay (`compose.observability.yml`) caps its services the same way — no container runs with the Docker default (uncapped):

| Service (overlay)                                                                                                          | max-size | max-file | Worst case |
| -------------------------------------------------------------------------------------------------------------------------- | -------- | -------- | ---------- |
| `prometheus`, `glitchtip`, `glitchtip-worker`, `glitchtip-db`, `prometheus-exporter`, `blackbox-exporter`, `pushgateway`    | 10m      | 3        | 30 MB      |
| `alertmanager`                                                                                                             | 10m      | 2        | 20 MB      |

New overlay services must ship with a `logging:` block — a structural test pins this (`test/observability/log_policy_test.rb`).

Read logs with `docker compose logs <service>` (`--since`, `--tail`); the rotated raw files live under `/var/lib/docker/containers/<id>/<id>-json.log*` on the host.

## Host file log → logrotate

The backup cron redirects script output to a plain file (see docs/ops/restore-runbook.md, "Scheduled operation"):

```cron
15 3 * * * cd /srv/civora-host && scripts/backup.sh >> log/backup.log 2>&1 && scripts/backup_prune.sh >> log/backup.log 2>&1
```

`log/backup.log` is the only host-side log file this repo produces; it rotates via logrotate — see [`logrotate.conf`](logrotate.conf) (weekly, 12 rotations, compress). Install it on the deploy host as `/etc/logrotate.d/civora-backup`.

## Log levels per environment

- `RAILS_LOG_LEVEL` env var overrides the level in every environment (`config/environments/production.rb`: defaults to `"info"`).
- Production default is **info**: system operation messages without per-request noise — deliberately, to minimise inadvertent PII exposure. Do not run production at `debug`.
- Development logs at `debug` by Rails default; test silences most output.

## Privacy rules

Logs are treated as an incidental data store, not a feature. Rules:

1. **No personal or sensitive payloads in log lines.** Never log request bodies, form params, tokens, mail content, or user records. If a bug needs parameter inspection, reproduce it locally against synthetic data.
2. **Rails parameter filtering stays on.** `config/initializers/filter_parameter_logging.rb` filters `passw, email, secret, token, _key, crypt, salt, certificate, otp, ssn`. Decidim adds its own filters on top (`decidim-core` engine: `document_number`, `postal_code`, `mobile_phone_number`) — do not remove any of them; extend the list when new sensitive attributes appear.
3. **Production keeps `attributes_for_inspect = [:id]`** (`config/environments/production.rb`) — record dumps in logs show ids, not attributes.
4. **Error tracking is privacy-hardened.** Sentry/GlitchTip runs with `send_default_pii = false`, and `config/initializers/sentry.rb`'s `before_send` hook strips request data and user information from every event before it leaves the process.
5. **The backup log contains script output only** — manifest summaries (timestamp, git sha, row counts), no dump contents. `backups/` itself is 0700 and its contents are treated as secret material (see docs/ops/secrets.md).
6. **New log statements get reviewed like code** — anything that could print user content needs a reason written next to it.
