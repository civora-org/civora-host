# Environments

The app runs in three defined environments. Staging is **defined but deliberately unprovisioned** — revisit when the first production deployment with real users approaches.

## Overview

| | development | test | staging | production |
|---|---|---|---|---|
| Rails env | `development` | `test` | `production` (reserved) | `production` |
| Infra | host Ruby, or Docker dev overlay | CI (GitHub Actions) | **none yet** | Docker Compose (`compose.yaml`) |
| Database | `decidim_app_development` (local Postgres, peer/trust auth) | `decidim_app_test` (CI service) | reserved: `decidim_app_staging` | `decidim_app_production` (Postgres 17 container) |
| Secrets source | `.env` (local only) | CI env / service defaults | reserved: `.env.staging` | `.env` via compose |
| Mail | letter_opener (Decidim default) | test adapter | — | `SMTP_*` (**unconfigured — see secrets.md**) |
| Storage | `./storage` (bind mount) | tmp | — | `app-storage` named volume, `STORAGE_PROVIDER=local` |
| Force SSL | n/a | n/a | — | `DECIDIM_FORCE_SSL=0` **temporary** until a TLS terminator exists |

## Parity notes

- **Same image everywhere it runs containerized** — dev overlay (`compose.dev.yml`) reuses the production `Dockerfile`/`compose.yaml`; only mounts, ports, and auth differ.
- **Same Postgres major** — production runs Postgres 17; the CI service was aligned to 17 so tests exercise the same engine. (Keep this true if either is bumped.)
- **Secrets never shared across environments** — each environment gets its own `SECRET_KEY_BASE`, DB credentials, and (later) SMTP credentials.
- `DECIDIM_FORCE_SSL=0` and boot-time `db:prepare` are documented temporary divergences (see README "Current limitations").

## Config surface per environment

- **development:** `.env` (gitignored; template `.env.example`), optionally `compose.dev.yml` env. Full variable inventory: [secrets.md](secrets.md).
- **test:** env provided by `.github/workflows/ci.yml` (`DATABASE_*` to the Postgres service container); no real secrets.
- **staging (reserved):** would mirror production exactly (`compose.yaml` + a `.env.staging`), run as a separate compose project (`docker compose -p civora-staging …`) against its own database and volumes. Promotion recipe: production compose file + staging env file.
- **production:** `.env` consumed by `compose.yaml` (env interpolation + `env_file`), GitHub Actions secrets for CI-only tokens.

## Revisit triggers for staging

Provision staging when any of these become true:

1. the first production deployment serves real users;
2. a migration or engine upgrade needs rehearsal against production-like data;
3. more than one person deploys.
