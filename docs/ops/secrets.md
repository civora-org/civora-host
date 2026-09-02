# Secrets management

How secrets are handled in the Civora host app. Policy first, inventory second.

## Policy

**Environment variables only.** Rails encrypted credentials are **retired/unused**:

- The entire config surface reads secrets from ENV — Rails `ENV.fetch` (`config/database.yml`) and `Decidim::Env` (`config/environments/production.rb`, `config/storage.yml`).
- Nothing in the app calls `Rails.application.credentials` (verified across `config/`).
- `config/credentials.yml.enc` and the local `config/master.key` are leftovers from the initial scaffold. They are intentionally left in place (deleting them is churn with no benefit), but **no secret may ever be added to credentials** — it would not be read.
- Rationale: credentials would introduce a second secret (`RAILS_MASTER_KEY`) that itself needs distributing to every container — the same distribution problem plus file bookkeeping, with no payoff for a single-environment deployment.

**Distribution:** the `.env` file (gitignored) is the single source, consumed by Docker Compose (`env_file` / interpolation) and shell tooling.

**No secrets in git, ever:**

- `.env` is gitignored; `.env.example` carries empty placeholders only.
- Pre-commit hook: [gitleaks](https://github.com/gitleaks/gitleaks) scans staged changes (`scripts/hooks/pre-commit`, install with `scripts/install-hooks.sh`). The hook warns and allows the commit if gitleaks is not installed — **CI is the hard gate**.
- CI: every PR and push to `main` runs a full-history gitleaks scan (`.github/workflows/ci.yml`, `secret-scan` job).
- GitHub-native secret scanning and push protection are **not available** for this repository (organization free plan). The gitleaks hook + CI scan are the compensating controls. If a secret does reach git history: **rotate the secret immediately**, then rewrite history (`git filter-repo`) — rotation first, history second.

## Secret inventory

| Secret | Used by | Lives in | Notes |
|---|---|---|---|
| `SECRET_KEY_BASE` | Rails session/cookie signing | `.env` (dev & prod) | rotate → invalidates sessions |
| `POSTGRES_PASSWORD` | Postgres auth (compose + `database.yml`) | `.env` | dev compose overlay uses trust auth instead |
| `DATABASE_USERNAME` / `DATABASE_PASSWORD` | `config/database.yml` | `.env` (prod), unset locally | local dev uses peer auth |
| `DATABASE_URL` | `config/database.yml` (production block) | unset | only if moving to a URL-style DB config |
| `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_AUTHENTICATION` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_DOMAIN` | production mailer (`config/environments/production.rb`) | **unset — production mail is not configured yet** | wire at first real deploy; see `.env.example` |
| `GITHUB_TOKEN` | Docker build (engine gem fetch) | `.env` | passed as BuildKit **secret mount**, never a build arg; not in image layers |
| `ENGINE_READ_TOKEN` | CI (private gem checkout) | GitHub Actions secret | fine-grained PAT, Contents: read on the engine repo |
| `STORAGE_PROVIDER` + `AWS_*` / `GCS_*` / `AZURE_*` | `config/storage.yml` | unset | dormant — only if object storage is adopted; then also `BACKUP_ENCRYPT_KEY` for encrypted offsite backups |
| `REDIS_URL`, `PORT`, `RAILS_MAX_THREADS`, `RAILS_LOG_*`, `RAILS_ASSET_HOST` | config (not secret) | compose / env | listed for completeness |
| OmniAuth / Maps / Etherpad / VAPID families | future `config/initializers/decidim.rb` | — | not in the surface yet; will arrive via `Decidim::Env` when the initializer lands |

Secrets are never shared between environments (see [environments.md](environments.md)).

## Handling rules

- Do not paste secret values into logs, issue comments, docs, or chat. Docs and examples use placeholders only.
- Backups contain internal data and must be treated as secret material — see the backup/restore runbook (`docs/ops/`, milestone #50).
- Rotation triggers: suspected leak, contributor offboarding with repo/Actions access, or at minimum annually.
