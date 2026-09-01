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

## Docker (scaffold only)

A generator-provided `Dockerfile` (single `FROM decidim/decidim:0.31.7` line) and `docker-compose.yml` exist as starting points. A real, production-usable container baseline is tracked as `civora-org/civora-platform#48`.

## License

AGPL-3.0, same as Decidim (see `LICENSE-AGPLv3.txt`).
