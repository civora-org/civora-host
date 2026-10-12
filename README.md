# Civora host app

The Civora host application. It is a [Decidim](https://decidim.org) 0.32.1 install that mounts the [`decidim-contracts_sk`](https://github.com/civora-org/decidim-contracts_sk) engine at `/contracts` (inside Decidim's locale scope, so the pages live at `/sk/contracts`; the old `/contracts` paths redirect permanently). The engine provides the Slovak public contracts workflow and catalogue. This repository adds the deployment, the Slovak-first shell and the operations tooling around it.

Issues for Civora are tracked in [`civora-org/civora-platform`](https://github.com/civora-org/civora-platform), not in this repository.

## Status

- **No production deployment exists yet.** Hosting for a municipality is provisioned when a pilot is close. Until then the stack runs locally in Docker.
- A **public demo** is documented in [`docs/ops/demo-server.md`](docs/ops/demo-server.md). It uses fictional data only and is wiped regularly. Nothing real may be put on it.
- The engine is pinned to a release tag, [v1.8.0](https://github.com/civora-org/decidim-contracts_sk/releases). The engine release notes are in its [CHANGELOG](https://github.com/civora-org/decidim-contracts_sk/blob/main/CHANGELOG.md).

## Versions

| Component | Version |
|---|---|
| Decidim | 0.32.1 (Rails 8.1) |
| `decidim-contracts_sk` | v1.8.0 (pinned in the `Gemfile`) |
| Ruby | 3.4.7 (`.ruby-version`) |
| libvips | system library for image processing (replaces ImageMagick in Decidim 0.32); `libvips42t64` in the image |
| Node.js | 22.14.0 (`.node-version`, for Shakapacker) |
| PostgreSQL | 17 (Compose and CI) |
| Redis | 7 (Compose; required by the production Action Cable config) |

## What the host adds to Decidim

- **Slovak-first shell**: contracts-only header and footer, the organisation's colours and logo, and a Slovak locale fix. See [Customisations](#customisations-over-decidim).
- **Participation links**: contracts can be linked to Accountability results and Budgets projects, and the linked contracts appear on those pages.
- **Admin second factor**: TOTP for admins and engine role holders, wired into the engine's second-factor seam. See [`docs/ops/two-factor.md`](docs/ops/two-factor.md).
- **Nightly CRZ sync**: a scheduler service imports the organisation's CRZ mirrors. See [`docs/ops/crz-sync.md`](docs/ops/crz-sync.md).
- **Accessibility statement**: a Slovak and English static page with a footer link. See [`docs/ops/accessibility-statement.md`](docs/ops/accessibility-statement.md).
- **Operations tooling**: backups, a backup-gated deploy, restore drills, observability and secrets handling. See [Operations](#operations).

## Stack

`compose.yaml` defines the base stack:

| Service | Image | Purpose |
|---|---|---|
| `app` | built from `Dockerfile` (`ruby:3.4.7-slim`, non-root user) | Rails and Decidim on port 3000. The entrypoint runs `db:prepare` and `db:seed` before starting the Rails server |
| `scheduler` | same image | Nightly CRZ sync loop (03:30 Europe/Bratislava). Runs `scripts/crz_sync_scheduler.sh` |
| `db` | `postgres:17` | Production database |
| `redis` | `redis:7-alpine` | Action Cable |

Overlays are selected with `COMPOSE_FILE` in `.env`, or with `-f`:

| File | Purpose |
|---|---|
| `compose.dev.yml` | Bind-mount development loop: `docker compose -f compose.yaml -f compose.dev.yml up` |
| `compose.tls.yml` | Caddy in front of the app with automatic Let's Encrypt certificates. Requires `SITE_ADDRESS` and `ACME_EMAIL` |
| `compose.observability.yml` | Self-hosted error tracking (GlitchTip), metrics (Prometheus), alerting (Alertmanager) and blackbox probes. See [`docs/ops/observability.md`](docs/ops/observability.md) |
| `compose.demo.yml` | Public demo overlay (`DEMO_MODE=1`, no CRZ, mail written to files). Used with `compose.tls.yml` |
| `compose.drill.yml` | Throwaway overlay for `scripts/restore_drill.sh` |

## Local development

Without Docker, using a host Ruby and a local PostgreSQL:

```bash
bundle install
DISABLE_SPRING=1 bin/rails db:create db:migrate db:seed

# one-time: gitleaks pre-commit hook (requires gitleaks, e.g. `brew install gitleaks`)
scripts/install-hooks.sh

bin/dev    # Rails on 0.0.0.0:3000 and the Shakapacker dev server (Procfile.dev)
```

Database settings come from the environment (`config/database.yml`): `DATABASE_HOST` (default `localhost`), `DATABASE_PORT` (5432), `DATABASE_USERNAME` and `DATABASE_PASSWORD` (blank means socket or peer authentication), and `DATABASE_URL` in production.

Prefix host-app `rails` and `rake` commands with `DISABLE_SPRING=1`. The Spring daemon otherwise keeps long-running sessions alive.

Smoke checks once the app runs:

| Path | Expected |
|---|---|
| `GET /up` | Rails liveness check (200) |
| `GET /healthz` | Database and Redis check. Returns 503 with a JSON status on failure |
| `GET /contracts` | Public catalogue of the engine |

## Docker quickstart

Requires Docker with Compose v2 and network access to GitHub. The engine is fetched from its public repository at build time.

```bash
cp .env.example .env
# set SECRET_KEY_BASE (openssl rand -hex 64) and POSTGRES_PASSWORD (openssl rand -hex 16)
# leave GITHUB_TOKEN empty unless you build a private fork

docker compose up -d --build
curl -fsS http://localhost:3000/contracts   # expect 200
```

A GitHub token is passed as a BuildKit secret mount, never as a build argument, so it does not appear in the image history or layers.

A clean-state smoke test runs the whole sequence (`down -v`, build, wait for healthy, `GET /contracts`):

```bash
scripts/smoke_test.sh
```

## Configuration

Copy `.env.example` to `.env`. Never commit `.env`. The full variable inventory and the rotation procedure are in [`docs/ops/secrets.md`](docs/ops/secrets.md).

| Variable | Required | Purpose |
|---|---|---|
| `SECRET_KEY_BASE` | yes | Rails secret. Rotating it invalidates encrypted data, so every TOTP enrolment must be reset with `two_factor:reset_all` (see [two-factor](docs/ops/two-factor.md)) |
| `POSTGRES_PASSWORD` | yes | Password of the `postgres` user in the Compose database |
| `DECIDIM_ORG_HOST` | before the first pilot boot | Host name the seeded organisation answers on (default `localhost`) |
| `GITHUB_TOKEN` | private forks only | Read access to a private engine fork during the build |
| `SMTP_*` | at the first real deploy | Production mail. Not configured yet |
| `CRZ_ICO_ORG_<organization id>` | to run the CRZ import | The organisation's IČO. Without it the import refuses to run |
| `CRZ_SYNC_INITIAL_SINCE` | optional | First-run cursor for the CRZ sync (default: 7 days ago) |
| `CRZ_SYNC_PUSHGATEWAY_URL` | optional | Dead-man push target for the sync (default: the in-network pushgateway) |
| `ACTOR_EMAIL` | optional | Pins the admin account used as audit actor by the CRZ sync (default: the first admin who accepted the terms) |
| `GLITCHTIP_SECRET_KEY`, `GLITCHTIP_DB_PASSWORD` | with the observability overlay | Required by the GlitchTip services |
| `SENTRY_DSN`, `GLITCHTIP_DOMAIN`, `PUSHGATEWAY_URL` | optional | Error tracking and metrics wiring |
| `ALERT_*` | with the observability overlay | Alert delivery: Telegram for critical and high alerts, e-mail for all |
| `SITE_ADDRESS`, `ACME_EMAIL` | with `compose.tls.yml` | Public host name and Let's Encrypt contact |

One Compose setting is deliberate for now: `DECIDIM_FORCE_SSL: "0"` in `compose.yaml`, because the base stack has no TLS terminator. Remove it once a reverse proxy terminates HTTPS, or use `compose.tls.yml`.

## Working on the engine alongside this app

The `Gemfile` pins the engine to a tag:

```ruby
gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.8.0"
```

To work on a local engine checkout, use a Bundler local override. Never commit it:

```bash
bundle config set --local local.decidim-contracts_sk /path/to/decidim-contracts_sk
git -C /path/to/decidim-contracts_sk checkout v1.8.0   # Bundler refuses any other revision

# when done
bundle config unset --local local.decidim-contracts_sk
```

Inside Docker, use a personal, untracked `docker-compose.override.yml` that mounts the engine checkout read-only at `/opt/decidim-contracts_sk`. Compose loads that file automatically, so pass `-f compose.yaml` explicitly when you want to run the built image.

## Upgrading the engine

1. Cut an engine release and bump `tag:` in the `Gemfile`.
2. Run `bundle lock --update decidim-contracts_sk --conservative`, review the lock diff and run `bundler-audit`.
3. Copy each **new** engine migration into `db/migrate/` verbatim, with its original timestamp and the `.decidim_contracts_sk.rb` suffix. Take it from the tag:
   ```bash
   git -C ../decidim-contracts_sk show v1.8.0:db/migrate/<file>.rb > db/migrate/<file-without-.rb>.decidim_contracts_sk.rb
   ```
4. Do **not** run `bin/rails decidim_contracts_sk:install:migrations` here. It re-stamps timestamps, and a database that already ran the engine migrations would run them again.
5. Migrate, commit the regenerated `db/schema.rb` (its diff should contain only the engine's tables, columns and the version), rebuild the image and walk through the [demo test plan](docs/qa/demo-test-plan.md).

Check the engine's `CHANGELOG.md` and its `docs/` for host follow-ups for each release.

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every pull request and on pushes to `main`:

- RuboCop;
- Minitest against PostgreSQL 17;
- Brakeman with `--exit-on-warn` and one documented ignore for the upstream-pinned end-of-life Rails warning (`config/brakeman.ignore`);
- `bundler-audit`, with per-advisory ignores that are blocked upstream, each with a revisit condition (`.bundler-audit.yml`);
- a full-history gitleaks scan (`.gitleaks.toml`).

The workflow still uses an `ENGINE_READ_TOKEN` secret to check out the engine. The engine repository is public, so that token is no longer needed and the checkout steps can be removed.

## Onboarding a municipality

The hosting model is one stack per city (ADR-011). Onboarding is scripted and idempotent, keyed by the organisation id. See [`docs/ops/onboard-municipality.md`](docs/ops/onboard-municipality.md) for the full procedure, including the steps that stay manual (DNS, TLS and the people).

```bash
bin/rails "civora:onboard:organization[config/onboarding/<city>.yml]"
bin/rails "civora:onboard:crz_sync[<organization_id>,<SINCE ISO8601>]"   # rate-limit aware, resumable
bin/rails "civora:onboard:verify[<organization_id>]"
```

`config/onboarding/example.yml` is the template. It uses `example.org` addresses only.

After onboarding, the pilot checklist in short:

1. Give the stack its own host name and HTTPS, then remove `DECIDIM_FORCE_SSL: "0"`.
2. Create a fresh database on the pilot host. A pilot is never a copy of the demo database.
3. Create the system admin, then set the default locale to `sk` and the organisation's logo and colours in `/system`.
4. Invite the municipality's admins. Each one enrols a second factor before using the admin. Check with `bin/rails two_factor:status`.
5. Make sure the pilot has at least two people with engine roles. The person who submits a contract cannot approve, return or reject it. A single-person municipality must opt out explicitly with `Decidim::ContractsSk.allow_self_review = true` in `config/initializers/contracts_sk.rb`. Self-reviews are then audited.
6. Schedule the CRZ sync, the search-alert digest (`decidim_contracts_sk:subscriptions:deliver`, daily) and the backups, and log one restore drill.
7. Walk the demo test plan on the pilot stack with `MANUAL-2026-` records, then archive them.

## Demo and QA

- **Demo data**: `bin/rails "decidim_contracts_sk:seed_demo[<organization_id>]"` seeds fictional contracts in every lifecycle state. It is idempotent. Never run it on a pilot database.
- **Demo admins**: `contracts-admin@example.org` and `contracts-editor@example.org`. The seed sets random passwords, stored in the git-ignored `tmp/demo-admin-credentials.txt`. Under the four-eyes rule, submit as the editor and decide as the admin.
- **Test plan**: [`docs/qa/demo-test-plan.md`](docs/qa/demo-test-plan.md) is the click-through run for each release. Test records use the `MANUAL-2026-` prefix and are archived after each run, because the demo database also supplies screenshots for [civora-org/civora-site](https://github.com/civora-org/civora-site).

## Customisations over Decidim

The engine provides markup only. The Civora look and content live in this repository:

| Area | Where |
|---|---|
| Colours, logo and print layer | [`docs/appearance.md`](docs/appearance.md), `app/packs/stylesheets/decidim/decidim_application.scss` |
| Header: Help and Zmluvy (the catalogue) instead of Meetings and Activity; a Participácia link when the town has published processes | `app/views/layouts/decidim/header/_main_links_desktop.html.erb`, `app/lib/participation_navigation.rb` |
| Homepage hero: a second button to the processes when they exist | `app/cells/decidim/content_blocks/hero/cta_button.erb` |
| Topbar search: submits to the catalogue's `q` filter | `app/views/layouts/decidim/header/_main_search.html.erb` |
| Footer: Resources holds Open Data only | `app/views/layouts/decidim/footer/_main_links.html.erb` |
| Slovak locale fix and footer copy | `config/locales/sk.yml` |
| Homepage hero, en and sk, idempotent | `db/seeds.rb` |
| Participation links: resolver and two view overrides | `app/lib/participation_link_resolver.rb`, `app/views/decidim/accountability/results/_result.html.erb`, `app/views/decidim/budgets/projects/show.html.erb` |
| Admin second factor | `app/lib/two_factor`, `app/controllers/two_factor`, `config/initializers/two_factor.rb` |
| Engine configuration seams | `config/initializers/contracts_sk.rb` |

The view overrides replace decidim-core, decidim-accountability and decidim-budgets 0.32.1 partials by path. Re-check them on every Decidim upgrade. A test fails when the two participation-link views, or the header links partial, drift from the installed gems.

Participation link setup: [`docs/ops/participation-link.md`](docs/ops/participation-link.md).

## Operations

### Documentation

| Document | Covers |
|---|---|
| [`docs/ops/secrets.md`](docs/ops/secrets.md) | Secrets policy, inventory, gitleaks guardrails, rotation |
| [`docs/ops/environments.md`](docs/ops/environments.md) | Development, test, staging and production definitions. Staging is defined but not provisioned |
| [`docs/ops/onboard-municipality.md`](docs/ops/onboard-municipality.md) | Scripted municipality onboarding |
| [`docs/ops/demo-server.md`](docs/ops/demo-server.md) | Public demo server: provisioning, deploy, TLS, nightly reset, teardown |
| [`docs/ops/demo-proposal-to-contract.md`](docs/ops/demo-proposal-to-contract.md) | Demo seed for a proposal, budget project, result and linked contract |
| [`docs/ops/crz-sync.md`](docs/ops/crz-sync.md) | Nightly CRZ sync scheduler |
| [`docs/ops/two-factor.md`](docs/ops/two-factor.md) | Admin TOTP: who must enrol, sign-in flow, lockout, operator reset |
| [`docs/ops/participation-link.md`](docs/ops/participation-link.md) | Contract links to results and projects |
| [`docs/ops/participation-navigation.md`](docs/ops/participation-navigation.md) | Header link, hero button and the homepage processes block (`civora:home:participation`) |
| [`docs/ops/accessibility-statement.md`](docs/ops/accessibility-statement.md) | Accessibility statement and its publishing task |
| [`docs/ops/restore-runbook.md`](docs/ops/restore-runbook.md) | Backup and restore procedures, deploy gate, scheduled operation |
| [`docs/ops/restore-drill-log.md`](docs/ops/restore-drill-log.md) | Log of executed restore drills |
| [`docs/ops/log-policy.md`](docs/ops/log-policy.md) | Where logs live, rotation, levels, privacy rules |
| [`docs/ops/observability.md`](docs/ops/observability.md) | Error tracking, metrics, alerting, backup dead-man switch |
| [`docs/ops/incident-response.md`](docs/ops/incident-response.md) | Roles, severity, response targets, breach notification (sk templates) |
| [`docs/ops/security-updates.md`](docs/ops/security-updates.md) | Patch cadence, emergency patches, review of upstream-blocked advisories |

### Scripts

| Script | Purpose |
|---|---|
| `scripts/backup.sh` | `pg_dump`, attachments archive, manifest and checksums in `backups/`, plus the dead-man ping |
| `scripts/backup_prune.sh` | Retention: 7 daily, 4 weekly and 6 monthly backups |
| `scripts/deploy.sh` | Backup-gated deploy: backup, verify, up, smoke test, monitoring review. Deploys must use it |
| `scripts/restore_drill.sh` | Restores into an isolated stack, verifies and logs the result |
| `scripts/smoke_test.sh` | Clean-state build and smoke test |
| `scripts/install-hooks.sh` | Installs the gitleaks pre-commit hook |
| `scripts/crz_sync_run.sh`, `scripts/crz_sync_scheduler.sh` | Run one CRZ sync pass, and the scheduler loop used by the `scheduler` service |

`scripts/deploy.sh` aborts unless a verified backup has been taken first. It also re-checks `/healthz` after the smoke test.

### Rake tasks

| Task | Purpose |
|---|---|
| `civora:onboard:organization[<config>]`, `civora:onboard:crz_sync[...]`, `civora:onboard:verify[...]` | Municipality onboarding |
| `civora:accessibility_statement:publish[<organization_id>]` | Publish the accessibility statement (idempotent) |
| `civora:demo:proposal_to_contract[<organization_id>]`, `civora:demo:prepare_server[...]` | Demo seeds |
| `two_factor:status`, `two_factor:reset`, `two_factor:reset_all` | List second-factor enrolment; reset one or all users (see [two-factor](docs/ops/two-factor.md)) |
| `decidim_contracts_sk:*` | Engine tasks: CRZ import, search-alert delivery, demo seed. See the [engine README](https://github.com/civora-org/decidim-contracts_sk#rake-tasks) |

### Backups and secrets

Backups run from `scripts/backup.sh` and are pruned by `scripts/backup_prune.sh`. Restore procedures and drills are in [`docs/ops/restore-runbook.md`](docs/ops/restore-runbook.md) and [`docs/ops/restore-drill-log.md`](docs/ops/restore-drill-log.md). Secrets come from environment variables only. Rails credentials are retired.

## Known limitations

- No production deployment exists yet. The stack has not run with real municipal data.
- Migrations run on boot (`db:prepare`). That is acceptable for one instance, not for replicated setups.
- The image is built for the host architecture only. Multi-architecture builds are a follow-up.
- Builds fetch the engine from GitHub, so they need network access. The tag pin keeps the result deterministic.
- The staging environment is defined but not provisioned.

## License

AGPL-3.0, the same licence as Decidim. See [`LICENSE-AGPLv3.txt`](LICENSE-AGPLv3.txt).
