# Civora host app

The [Civora](https://github.com/civora-org) host application: a [Decidim](https://decidim.org) 0.31.7 install with the [`decidim-contracts_sk`](https://github.com/civora-org/decidim-contracts_sk) engine (Slovak public contracts workflow & catalogue) mounted at `/contracts`.

Part of the Civora platform; issues are tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform), not here.

## Requirements

- Ruby **3.3.4** (see `.ruby-version`)
- Node.js **22.14.0** (see `.node-version`) — for Shakapacker asset compilation
- PostgreSQL (14+ recommended), reachable at `localhost:5432` by default
- A GitHub account with read access to `civora-org` private repos (the engine is consumed as a tagged git source)

## Setup

```bash
# Authenticate git for GitHub (one-time, any of):
gh auth setup-git          # HTTPS via GitHub CLI token (recommended)
# …or ensure your SSH key is registered with GitHub

bundle install
DISABLE_SPRING=1 bin/rails db:create db:migrate db:seed
```

Database connection is env-driven (`config/database.yml`):
`DATABASE_HOST` (default `localhost`), `DATABASE_PORT` (5432), `DATABASE_USERNAME`/`DATABASE_PASSWORD` (blank = local socket/peer auth), `DATABASE_URL` (production).

> **`DISABLE_SPRING=1`** — prefix host-app `rails`/`rake` commands with it; the Spring daemon otherwise swallows long-running tool sessions.

## Development

```bash
bin/dev        # rails server (0.0.0.0:3000) + Shakapacker dev server (Procfile.dev)
```

Smoke checks once running:

- `GET /up` — Rails health endpoint (also the uptime target for monitoring)
- `GET /contracts` — the contracts engine's public catalogue

## Working on the engine alongside this app

The Gemfile pins the engine deterministically:

```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v0.6.0"
```

To hack on the engine locally, use Bundler's local override (never commit it):

```bash
bundle config set --local local.decidim-contracts_sk /path/to/decidim-contracts_sk
# …and check the engine out at the pinned revision first:
git -C /path/to/decidim-contracts_sk checkout v0.6.0

# when done:
bundle config unset --local local.decidim-contracts_sk
```

The local checkout **must** sit at the pinned revision, otherwise Bundler refuses — that is deliberate: the host always boots a reproducible engine version. Advancing the engine means cutting an engine release and bumping the tag here.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every PR and push to `main`: rubocop, minitest (Postgres service), brakeman (`--exit-on-warn`, one documented ignore for the upstream-pinned EOL Rails warning — `config/brakeman.ignore`), and bundler-audit (per-advisory ignores in `.bundler-audit.yml`, all provably upstream-blocked with revisit conditions).

CI authenticates to the private engine repository via the `ENGINE_READ_TOKEN` secret (fine-grained PAT, Contents: read-only on `civora-org/decidim-contracts_sk`) — rotate it in GitHub → Settings → Developer settings → Fine-grained tokens, then `gh secret set ENGINE_READ_TOKEN --repo civora-org/civora-host`.

## Docker

Production-baseline container stack (tracked as `civora-org/civora-platform#48`):

- **`Dockerfile`** — multi-stage build on `ruby:3.3.4-slim` (matching the pinned Ruby). The builder stage installs the toolchain and compiles assets; the runtime stage has no build tools, runs as non-root user `rails` (UID 1000), and ships only runtime libs (`libpq5`, `libjemalloc2`, `libicu`, ImageMagick/Vips).
- **`compose.yaml`** — prod-baseline stack: `app` + Postgres 17 + Redis (required by the production ActionCable config). Healthchecks on all three services (`/up` for the app). Migrations and the idempotent seed run on boot via `bin/docker-entrypoint`.
- **`compose.dev.yml`** — overlay restoring the bind-mount dev loop:
  `docker compose -f compose.yaml -f compose.dev.yml up`

### Build & run (clean machine)

Prerequisites: Docker with Compose v2 and a GitHub token with read access to `civora-org/decidim-contracts_sk` (the engine gem is fetched from the private repo at build time).

```bash
cp .env.example .env                       # then fill in:
#   POSTGRES_PASSWORD=<random hex>        (openssl rand -hex 16)
#   SECRET_KEY_BASE=<random hex>          (openssl rand -hex 64)
#   GITHUB_TOKEN=<token with repo read>

GITHUB_TOKEN="$(grep GITHUB_TOKEN .env | cut -d= -f2)" docker compose up -d --build
curl -fsS http://localhost:3000/contracts  # -> 200
```

The token is passed as a BuildKit **secret mount**, never a build arg — it is not present in image history or layers (verified with `docker history --no-trunc` / `docker save | grep`).

A full clean-state smoke test is available:

```bash
GITHUB_TOKEN=... scripts/smoke_test.sh   # down -v -> build -> healthy -> GET /contracts -> 200
```

### Current limitations

- `DECIDIM_FORCE_SSL=0` is set because no TLS terminator exists yet; remove the override once a reverse proxy terminates HTTPS in front of `app`.
- Migrations run on boot (`db:prepare`) — acceptable for a single instance, not for replicated setups.
- Built for the host architecture only; multi-arch (buildx) is a follow-up.
- The engine gem is fetched from GitHub at build time, so builds need network + token; the tag pin (`v0.6.1`) keeps the result deterministic.

## Operations

Secrets handling, environments, and backup/restore are documented under `docs/ops/`:

- [`docs/ops/secrets.md`](docs/ops/secrets.md) — secrets policy (env vars only; Rails credentials retired), full inventory, gitleaks guardrails, rotation procedure
- [`docs/ops/environments.md`](docs/ops/environments.md) — dev/test/production definitions, parity notes, staging-on-paper
- [`docs/ops/restore-runbook.md`](docs/ops/restore-runbook.md) — backup/restore procedures, deploy gate, scheduled operation
- [`docs/ops/restore-drill-log.md`](docs/ops/restore-drill-log.md) — executed restore drills (quarterly + after script changes)

Operational scripts:

```bash
scripts/backup.sh            # pg_dump + attachments tar + manifest + sha256 -> backups/
scripts/backup_prune.sh      # retention: 7 daily / 4 weekly / 6 monthly
scripts/deploy.sh            # backup-gated deploy: backup -> verify -> up -> smoke
scripts/restore_drill.sh     # full restore into an isolated stack, verified + logged
scripts/install-hooks.sh     # gitleaks pre-commit hook
```

Deploys must go through `scripts/deploy.sh` — it aborts unless a verified backup was taken first (the "Backup completed" gate from the platform CI/CD plan).

## License

AGPL-3.0, same as Decidim (see `LICENSE-AGPLv3.txt`).
