# Civora host app

The [Civora](https://github.com/civora-org) host application: a [Decidim](https://decidim.org) 0.31.7 install with the [`decidim-contracts_sk`](https://github.com/civora-org/decidim-contracts_sk) engine (Slovak public contracts workflow & catalogue) mounted at `/contracts`.

Part of the Civora platform; issues are tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform), not here.

## Pilot release

The first release offered to municipalities is a **pilot**: one organization per stack, Slovak UI, a 3-month run on real (public) contract data.

| Component | Version |
|---|---|
| Decidim | 0.31.7 |
| `decidim-contracts_sk` | **v1.7.1** (contract workflow, four-eyes review, privacy-redaction gate, audit trail, CRZ deadline tracking and filing confirmation, admin home, CRZ mirror import scoped to the organization's IČO, workflow notifications, role assignment, internal notes, contract templates, spreadsheet import; public results-first catalogue with filters and sorting, supplier pages, statistics, CSV/JSON open-data export, Atom feed, e-mail search alerts, SEO meta and sitemap; a Decidim component for participatory spaces) |
| Ruby / Postgres | 3.3.4 / 17 |

What a pilot stack serves:

- `/contracts`: public catalogue (search, register of published contracts with amounts) and contract detail (facts panel, parties, documents, version history, CRZ provenance notice);
- `/contracts/admin/contracts`: the editor/reviewer workflow (draft → review → redaction confirmation → publish → amendments), the CRZ import and `/contracts/admin/audit_events`;
- a Slovak-first Decidim shell: contracts-only header and footer, institutional palette and logo (see [Customisations](#customisations-over-decidim)).

Before the first pilot deploy, work through the [pilot readiness checklist](#pilot-readiness-checklist).

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

# one-time: install the gitleaks pre-commit hook (secret scanning)
scripts/install-hooks.sh    # requires `brew install gitleaks` (or equivalent)
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
- `GET /healthz` — deep health check: database + Redis connectivity (also a monitored probe; 503 + JSON status on failure)
- `GET /contracts` — the contracts engine's public catalogue

## Working on the engine alongside this app

The Gemfile pins the engine deterministically:

```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.7.1"
```

To hack on the engine locally, use Bundler's local override (never commit it):

```bash
bundle config set --local local.decidim-contracts_sk /path/to/decidim-contracts_sk
# …and check the engine out at the pinned revision first:
git -C /path/to/decidim-contracts_sk checkout v1.7.1

# when done:
bundle config unset --local local.decidim-contracts_sk
```

The local checkout **must** sit at the pinned revision, otherwise Bundler refuses — that is deliberate: the host always boots a reproducible engine version. Advancing the engine means cutting an engine release and bumping the tag here.

Inside Docker, the same loop works with a personal, untracked `docker-compose.override.yml` that bind-mounts the engine checkout (read-only) at `/opt/decidim-contracts_sk` and swaps in a Gemfile using `path: "/opt/decidim-contracts_sk"`. Docker Compose loads an override file automatically, so run the real image with `docker compose -f compose.yaml …` (or pin `COMPOSE_FILE` in `.env`) whenever you are not developing the engine.

### Upgrading the engine

1. Cut the engine release (release-please PR in the engine repo) and bump `tag:` in the `Gemfile`.
2. `bundle lock --update decidim-contracts_sk --conservative`; review the lock diff and run `bundler-audit`.
3. Copy every **new** engine migration into `db/migrate/` **verbatim, keeping its original timestamp**, named `<timestamp>_<name>.decidim_contracts_sk.rb` (the vendored-migration pattern, excluded from rubocop):
   ```bash
   git -C ../decidim-contracts_sk show v1.7.1:db/migrate/<file>.rb > db/migrate/<file-without-.rb>.decidim_contracts_sk.rb
   ```
   Do **not** use `bin/rails decidim_contracts_sk:install:migrations` here: it re-stamps the timestamps, and databases that already ran the engine migrations would run them again.

   v1.7.1 ships four migrations, copied verbatim with their original timestamps: `20261006000001` (`decidim_contracts_sk_user_roles`), `20261006000002` (`decidim_contracts_sk_notes`), `20261006000003` (`decidim_contracts_sk_templates`), `20261006000004` (`decidim_contracts_sk_subscriptions`). Host follow-ups that come with it: schedule the e-mail alerts digest task and configure SMTP (engine `docs/search-alerts.md`); reference `/contracts/sitemap.xml` from `robots.txt`; optionally wire the related-contracts block into Decidim result/project pages (engine `docs/related-contracts.md`, civora-org/civora-platform#130/#131) and add the "Zmluvy" component to a participatory space (engine `docs/decidim-component.md`).

   v1.5.0 ships two migrations, both reversible:
   - `20261003000001_add_submitted_by_to_decidim_contracts_sk_contracts.rb` (four-eyes, [civora-org/civora-platform#123](https://github.com/civora-org/civora-platform/issues/123)) adds the nullable `decidim_submitted_by_id` column and backfills it from the audit trail (the actor of each contract's latest `contract.submit` row), so contracts already in review stay blocked for their submitter.
   - `20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb` (CRZ filing confirmation, [civora-org/civora-platform#125](https://github.com/civora-org/civora-platform/issues/125)) adds three nullable columns: `crz_filed_at`, `crz_published_on`, `crz_filing_reason`. No backfill.

   Behaviour change in v1.5.0: the CRZ deadline badge now clears only when the filing is confirmed through the admin action *Record CRZ filing*. Records that only carry a hand-typed `crz_url` show the badge again until someone confirms them.
4. Run the migrations and commit the regenerated `db/schema.rb`; its diff must contain only the engine's tables, columns and the version.
5. Rebuild the image and walk §0–§3 of the [demo test plan](docs/qa/demo-test-plan.md).

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every PR and push to `main`: rubocop, minitest (Postgres 17 service, matching production), brakeman (`--exit-on-warn`, one documented ignore for the upstream-pinned EOL Rails warning — `config/brakeman.ignore`), bundler-audit (per-advisory ignores in `.bundler-audit.yml`, all provably upstream-blocked with revisit conditions), and a full-history gitleaks secret scan (`.gitleaks.toml`).

CI authenticates to the private engine repository via the `ENGINE_READ_TOKEN` secret (fine-grained PAT, Contents: read-only on `civora-org/decidim-contracts_sk`) — rotate it in GitHub → Settings → Developer settings → Fine-grained tokens, then `gh secret set ENGINE_READ_TOKEN --repo civora-org/civora-host`.

## Docker

Production-baseline container stack (tracked as `civora-org/civora-platform#48`):

- **`Dockerfile`** — multi-stage build on `ruby:3.3.4-slim` (matching the pinned Ruby). The builder stage installs the toolchain and compiles assets; the runtime stage has no build tools, runs as non-root user `rails` (UID 1000), and ships only runtime libs (`libpq5`, `libjemalloc2`, `libicu`, ImageMagick/Vips).
- **`compose.yaml`** — prod-baseline stack: `app` + Postgres 17 + Redis (required by the production ActionCable config). Healthchecks on all three services (`/up` for the app). Migrations and the idempotent seed run on boot via `bin/docker-entrypoint`.
- **`compose.dev.yml`** — overlay restoring the bind-mount dev loop:
  `docker compose -f compose.yaml -f compose.dev.yml up`

> A personal `docker-compose.override.yml` (see [Working on the engine](#working-on-the-engine-alongside-this-app)) is picked up by every plain `docker compose` command. Pass `-f compose.yaml` explicitly, or pin `COMPOSE_FILE` in `.env`, to be sure you run the built image.

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

- `DECIDIM_FORCE_SSL=0` is set in `compose.yaml` because the base stack has no TLS terminator; the `compose.tls.yml` overlay (Caddy, automatic Let's Encrypt, `DECIDIM_FORCE_SSL=1`, [`docs/ops/demo-server.md`](docs/ops/demo-server.md)) provides one.
- Migrations run on boot (`db:prepare`) — acceptable for a single instance, not for replicated setups.
- Built for the host architecture only; multi-arch (buildx) is a follow-up.
- The engine gem is fetched from GitHub at build time, so builds need network + token; the tag pin (`v1.7.1`) keeps the result deterministic.

## Customisations over Decidim

The engine stays markup-only; everything that makes the shell look and read like Civora lives here:

- **Visual identity**: organization colours, logo and the print layer — [`docs/appearance.md`](docs/appearance.md) and `app/packs/stylesheets/decidim/decidim_application.scss`.
- **Header** (`app/views/layouts/decidim/header/_main_links_desktop.html.erb`): Help and **Zmluvy** (the catalogue) instead of Meetings and Activity, which carry no content on a contracts-only platform.
- **Topbar search** (`app/views/layouts/decidim/header/_main_search.html.erb`): submits to the catalogue's own `q` filter; Decidim's global search indexes participatory spaces, which this platform has none of.
- **Footer** (`app/views/layouts/decidim/footer/_main_links.html.erb`): Resources is Open Data only; the Help column renders only when help topics are configured for the footer.
- **Locale** (`config/locales/sk.yml`): fixes decidim-core 0.31.7's "Vitajte na%{organization}" (missing space) and replaces the participation call to action in the footer with contracts-register copy.
- **Homepage hero** (`db/seeds.rb`): welcome text and a "Prezrieť zmluvy" button into `/contracts`, en + sk, idempotent.

- **Participation link** (civora-org/civora-platform#130, #131): contracts can be linked to Accountability results and Budgets projects, and the linked published contracts are listed on those Decidim pages. Organization-scoped resolver in `app/lib/participation_link_resolver.rb`, wired in `config/initializers/contracts_sk.rb`; two view overrides (`app/views/decidim/accountability/results/_project.html.erb`, `app/views/decidim/budgets/projects/show.html.erb`). To link in the admin: edit a contract at `/contracts/admin/contracts`, **Links** card, pick the target type and enter the numeric id from the result or project URL. See [`docs/ops/participation-link.md`](docs/ops/participation-link.md).

These override decidim-core 0.31.7 partials by path: re-check them on every Decidim upgrade. The two participation-link views are decidim-accountability / decidim-budgets 0.31.7 copies; a test fails when they drift from the installed gems.

## Demo and QA

- **Demo data:** `bin/rails "decidim_contracts_sk:seed_demo[<organization_id>]"` seeds fictional contracts in every lifecycle state (idempotent). Never run it on a pilot database.
- **Demo admins:** `contracts-admin@example.org` and `contracts-editor@example.org`; the seed sets random passwords. With the four-eyes rule (engine v1.5.0 onwards), one admin cannot judge their own submission. Submit as `contracts-editor@example.org` and return, approve or reject as `contracts-admin@example.org`. Reset them locally and keep them in `tmp/demo-admin-credentials.txt` (gitignored) — never in a committed file.
- **Manual test plan:** [`docs/qa/demo-test-plan.md`](docs/qa/demo-test-plan.md), the click-through for every release. Test records use the `MANUAL-2026-` prefix and are archived at the end of a run, because the demo database is also the sales demo and the source of the civora.sk screenshots ([`civora-org/civora-site`](https://github.com/civora-org/civora-site)).

## Pilot readiness checklist

A pilot stack is a fresh database on its own host — never a copy of the demo database.

1. **Host and TLS:** a domain for the municipality and a reverse proxy terminating HTTPS in front of `app`; then remove `DECIDIM_FORCE_SSL: "0"` from `compose.yaml` (see [Current limitations](#current-limitations)).
2. **Environment:** `.env` from `.env.example` with fresh secrets (`openssl rand -hex 64` / `-hex 16`), `DECIDIM_ORG_HOST=<pilot domain>` so the seeded organization answers on it, and SMTP configured (password resets and invitations need mail).
3. **First boot:** `scripts/deploy.sh` (backup-gated build, migrate, seed, smoke). Then `docker compose exec app bin/rails decidim_system:create_admin` for the system admin, and in `/system`: organization name, **default locale `sk`** (the seed defaults to `en`), the municipality's logo and colours.
4. **People:** invite the municipality's admins from `/admin` → Participants → Admins. Organization admins hold both engine roles (editor and reviewer) by default; narrow that with `Decidim::ContractsSk.role_resolver` in an initializer if the municipality separates the roles. From engine v1.5.0 onwards ([civora-org/civora-platform#123](https://github.com/civora-org/civora-platform/issues/123)), the person who submits a contract for review can never return, approve or reject it. The pilot therefore needs **at least two people with engine roles**. A one-person municipality must opt out explicitly in `config/initializers/contracts_sk.rb`; its self-reviews are then audited as `contract.approve_self` / `return_self` / `reject_self`:
   ```ruby
   Decidim::ContractsSk.allow_self_review = true
   ```
   The setting exists from engine v1.5.0; an older pin does not define it and would fail to boot.
5. **Content:** import the municipality's existing CRZ contracts (`bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE ISO8601>]"`), schedule it nightly, and add the terms-of-service page and a privacy notice in `/admin` → Pages.
6. **Operations:** observability overlay on (`COMPOSE_FILE` in `.env`), backups scheduled and one restore drill logged ([`docs/ops/restore-runbook.md`](docs/ops/restore-runbook.md)), alert webhook set.
7. **Acceptance:** walk the [demo test plan](docs/qa/demo-test-plan.md) on the pilot stack with `MANUAL-2026-` records, then archive them.

## Operations

Secrets handling, environments, backup/restore, logging, observability, incident response and security updates are documented under `docs/ops/`:

- [`docs/ops/secrets.md`](docs/ops/secrets.md) — secrets policy (env vars only; Rails credentials retired), full inventory, gitleaks guardrails, rotation procedure
- [`docs/ops/environments.md`](docs/ops/environments.md) — dev/test/production definitions, parity notes, staging-on-paper
- [`docs/ops/participation-link.md`](docs/ops/participation-link.md) — contract links to Accountability results and Budgets projects, view overrides, how to link in the admin
- [`docs/ops/demo-proposal-to-contract.md`](docs/ops/demo-proposal-to-contract.md) — idempotent demo seed `civora:demo:proposal_to_contract`: proposal, budget project, result and the linked contract (#132)
- [`docs/ops/demo-server.md`](docs/ops/demo-server.md) — public demo server on a ~5 EUR/month VPS: `bin/demo-provision`, `bin/demo-deploy`, Caddy TLS overlay (`compose.tls.yml`, #168), demo-only safety, nightly reset, teardown
- [`docs/ops/restore-runbook.md`](docs/ops/restore-runbook.md) — backup/restore procedures, deploy gate, scheduled operation
- [`docs/ops/restore-drill-log.md`](docs/ops/restore-drill-log.md) — executed restore drills (quarterly + after script changes)
- [`docs/ops/log-policy.md`](docs/ops/log-policy.md) — where logs live, rotation (Docker json-file + host logrotate), levels, privacy rules
- [`docs/ops/observability.md`](docs/ops/observability.md) — self-hosted error tracking (GlitchTip), metrics (Prometheus), alerting (Alertmanager), backup dead-man switch, synthetic-failure tests
- [`docs/ops/incident-response.md`](docs/ops/incident-response.md) — roles, severity and response targets, evidence preservation, GDPR art. 33 breach notification (sk templates)
- [`docs/ops/security-updates.md`](docs/ops/security-updates.md) — patch cadence, emergency patches, review of the upstream-blocked advisories in `.bundler-audit.yml`

Operational scripts:

```bash
scripts/backup.sh            # pg_dump + attachments tar + manifest + sha256 -> backups/ (+ dead-man ping)
scripts/backup_prune.sh      # retention: 7 daily / 4 weekly / 6 monthly
scripts/deploy.sh            # backup-gated deploy: backup -> verify -> up -> smoke -> monitoring review
scripts/restore_drill.sh     # full restore into an isolated stack, verified + logged
scripts/install-hooks.sh     # gitleaks pre-commit hook
```

Deploys must go through `scripts/deploy.sh` — it aborts unless a verified backup was taken first (the "Backup completed" gate from the platform CI/CD plan) and re-checks deep health (`/healthz`) after the smoke test.

Self-hosted monitoring (GlitchTip, Prometheus, Alertmanager, blackbox probes, pushgateway) rides on a compose overlay. Compose file selection is driven by `COMPOSE_FILE` (read by docker compose from `.env`):

```bash
echo 'COMPOSE_FILE=compose.yaml:compose.observability.yml' >> .env
docker compose up -d
```

Without that line (and on machines without `compose.observability.yml`), plain `docker compose` and the ops scripts run the base stack only.

## License

AGPL-3.0, same as Decidim (see `LICENSE-AGPLv3.txt`).
