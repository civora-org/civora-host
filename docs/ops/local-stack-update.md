# Updating the local dev stack

How to move the local Docker stack (the one used for sales demos) to newer host and engine code. Each run is recorded in the [update log](#update-log) at the end.

This is **not** a production deploy. There is no production host yet; for a server, see [demo-server.md](demo-server.md).

## How the local stack is put together

| Part | Where the code comes from | How it changes |
|---|---|---|
| Host app (`civora-host`) | **Baked into the Docker image** `civora-host:latest` | `git pull` + `docker compose build app` |
| Engine (`decidim-contracts_sk`) | **Mounted** from the engine repo's worktree `.claude/worktrees/host-main` (read-only bind mount at `/opt/decidim-contracts_sk`) | `git checkout` in that worktree + puma restart |
| Gemfile inside the container | `Gemfile.dev-engine` (uncommitted, bind-mounted over `/app/Gemfile`): a copy of `Gemfile` with the engine line switched to `path:` | Regenerate whenever `Gemfile` changes |
| Dev image | `civora-host:dev`, built from `Dockerfile.dev` (uncommitted): the production image plus `git`, which the path-mounted engine's gemspec needs | Rebuild after every `civora-host:latest` build (step 5) |
| Dev overrides | `docker-compose.override.yml` (uncommitted): runs `civora-host:dev`, starts puma itself, the mounts above, `BUNDLE_FROZEN=0` | Rarely |
| Database | Postgres volume, database `decidim_app_production` | Migrations |

Three uncommitted files make this work: `Gemfile.dev-engine`, `docker-compose.override.yml` and `Dockerfile.dev`. Don't delete them, and don't commit them. Their contents are at the end of this page, so they can be recreated.

Since 2026-10-12, **puma starts by itself** when the container starts (`bundle install --local` first, then puma), so a Docker or laptop restart brings the site back in about 10 seconds. Before that, the override ran `sleep infinity` and puma had to be started by hand; a Docker Desktop restart left the demo site down.

## Procedure

Run the steps in order. Expect 15–20 minutes, plus the time any data backfill needs.

1. **Back up the database.**
   ```bash
   docker exec civora-host-db-1 pg_dump -U postgres -Fc decidim_app_production > backups/pre-update-$(date +%F).dump
   ```
   Check it: a real dump is about 1 MB or more. A 1 KB file means the wrong database name.
   ```bash
   docker cp backups/pre-update-$(date +%F).dump civora-host-db-1:/tmp/pre.dump
   docker exec civora-host-db-1 pg_restore -l /tmp/pre.dump | grep -c "TABLE DATA"
   ```
   The count should be over 100.

2. **Update the host checkout.**
   ```bash
   git pull --ff-only
   ```

3. **Regenerate `Gemfile.dev-engine`.** Copy `Gemfile` with the engine line swapped for the worktree path. Write it with `cat >` so the bind-mounted file keeps its inode.
   ```bash
   sed 's#^gem "decidim-contracts_sk", github: .*#gem "decidim-contracts_sk", path: "/opt/decidim-contracts_sk/.claude/worktrees/host-main"#' Gemfile > /tmp/gde && cat /tmp/gde > Gemfile.dev-engine
   ```

4. **Move the engine worktree** to the engine version you want, e.g. the latest `main`:
   ```bash
   git -C ~/Code/decidim-contracts_sk/.claude/worktrees/host-main fetch origin
   git -C ~/Code/decidim-contracts_sk/.claude/worktrees/host-main checkout --detach origin/main
   ```

5. **Rebuild the images and recreate the containers.** The build takes 2–5 minutes. Build the production image first, then the dev image on top of it. (`docker compose build app` does nothing here, because the override removes the app's `build:`.)
   ```bash
   docker build -t civora-host:latest .
   docker build -t civora-host:dev -f Dockerfile.dev .
   docker compose up -d app scheduler
   ```

6. **Check the bundle.** The container resolves it on start (`bundle install --local`). Check that it uses the mounted engine:
   ```bash
   docker exec civora-host-app-1 bundle info decidim-contracts_sk
   ```
   Its `Path:` must be the `host-main` worktree.

7. **Copy new engine migrations verbatim, then migrate.** Copy each engine migration that the host does not have yet as `<same timestamp>_<same name>.decidim_contracts_sk.rb`.
   - **Never** run `decidim_contracts_sk:install:migrations` in the container: it re-stamps the versions.
   - The host repo gets the same files when the engine is pinned to a release.
   ```bash
   docker exec civora-host-app-1 sh -c 'cp /opt/decidim-contracts_sk/.claude/worktrees/host-main/db/migrate/<file>.rb /app/db/migrate/<file-without-.rb>.decidim_contracts_sk.rb'
   docker exec civora-host-app-1 sh -c 'cd /app && bin/rails db:migrate'
   ```

8. **Restart the app** so puma loads the migrated schema:
   ```bash
   docker restart civora-host-app-1
   ```
   Puma's output is in `docker logs civora-host-app-1`.

9. **Smoke check.** Each of these should return `200`:
   ```bash
   for u in http://localhost:3000/ http://localhost:3000/contracts http://localhost:3000/processes http://vranov.localhost:3000/contracts; do curl -s -o /dev/null -w "%{http_code} $u\n" $u; done
   ```
   Then click through the demo once in a browser.

10. **Run any data tasks** the update notes ask for (backfills), and add an entry to the [update log](#update-log).

### Rolling back

```bash
docker exec civora-host-app-1 pkill -f puma
docker cp backups/pre-update-<date>.dump civora-host-db-1:/tmp/pre.dump
docker exec civora-host-db-1 pg_restore -U postgres --clean --if-exists -d decidim_app_production /tmp/pre.dump
git checkout <previous host commit>
git -C ~/Code/decidim-contracts_sk/.claude/worktrees/host-main checkout --detach <previous engine commit>
```

Then repeat steps 3, 5, 6 and 8.

## Update log

### 2026-10-11 — host `99ce586` → `19a42cc`, engine `v1.7.1` → `main` @ `51665d3`

**Backup:** `backups/pre-update-2026-10-11.dump` (1 MB, 131 tables).

**What came in — host**

| PR | Change |
|---|---|
| civora-host#23 | Incident response docs |
| civora-host#24 | Engine pin v1.7.x |
| civora-host#25 | Participation link: contracts ↔ budget projects / results |
| civora-host#26 | Demo seed "proposal → project → result → contract" |
| civora-host#27 | Public demo server kit (Caddy TLS overlay, provisioning scripts) |
| civora-host#28 | README for the public repo |
| civora-host#29 | Scripted onboarding of a new municipality (`civora:onboard:*`, `bin/crz-first-sync`) |
| civora-host#30 | Accessibility statement page (`/pages/accessibility`) + footer link |
| civora-host#31 | **Two-factor login (TOTP) for admins and role holders** |

**What came in — engine** (not released yet; the stack runs `main`)

| PR | Change |
|---|---|
| decidim-contracts_sk#137 | Party filter matches only parties with an IČO (privacy) |
| decidim-contracts_sk#140 | Open data CSV/JSON: `crz_published_on` column |
| decidim-contracts_sk#141 | Admin accessibility fixes (contrast, keyboard-reachable tables) |
| decidim-contracts_sk#143 | Runs on Decidim 0.31 and 0.32 |
| decidim-contracts_sk#144 | **CRZ attachments: "Prílohy (v CRZ)" links on imported contracts** |

**Migrations run**

- `20261011000001_create_decidim_contracts_sk_crz_attachments` (engine, copied verbatim)
- `20261011100000_create_two_factor_tables` (host)

**Data tasks**
- Ran `CONFIRM=1 bin/rails "decidim_contracts_sk:crz_import:backfill_attachments[<org>]"` for org 3 (Vranov nad Topľou, 1 315 mirrors) and org 1 (Považská Bystrica). It fetches each contract once from ekosystem, about 1.1 s apart because of the rate limit, and stores only links; no files are downloaded.

**What behaves differently after this update**
- **Admin login needs an authenticator app.** On the first visit to `/admin` after signing in, every admin and contract role holder is sent to enrolment:
  1. scan the QR code with an authenticator app;
  2. enter the 6-digit code;
  3. **save the 10 recovery codes**.

  After that, every login asks for a code. If you lose the phone:
  ```bash
  docker exec civora-host-app-1 bin/rails "two_factor:reset[<email>]"
  ```
  Details are in [two-factor.md](two-factor.md).
- **Imported CRZ contracts** show a "Prílohy (v CRZ)" section that links to the official files on crz.gov.sk.
- The footer has a link to the accessibility statement.

**Gotchas hit this time**
- The first backup used the wrong database name and produced a 1 KB file. The real database is `decidim_app_production`.
- `bundle install` failed with "No such file or directory - git" because the image has no git. Step 6 handles it.
- `Gemfile.dev-engine` had to be regenerated because the host `Gemfile` gained `rotp` (step 3).

### 2026-10-11 (evening) — host `19a42cc` → `6f453de`, engine `main` → tag `v1.8.0`

**Backup:** `backups/pre-update-2026-10-11b.dump` (1.1 MB).

**What came in**
- Host: participation navigation (civora-host#33), demo test plan refresh (#35), engine pin v1.8.0 (#36).
- Engine: back on a release tag, v1.8.0. It is `main` from the morning update plus the hidden empty "Dokumenty" section on CRZ mirrors.

**Steps:** 1–9 of the procedure. No new migrations (the CRZ attachments migration had already run in the morning). Then:
```bash
bin/rails "civora:home:participation[1]"
bin/rails "civora:home:participation[3]"
```

**Data tasks:** the attachment backfill finished before the rebuild.
- Vranov (org 3): 1 311 of 1 315 contracts have links; 4 have none in CRZ.
- Považská Bystrica (org 1): 640 updated, 5 fail on every retry. They are probably removed from CRZ; check them by id if it matters.

**Demo data:** Vranov (org 3) got the labelled demo process "UKÁŽKA – Participatívny rozpočet (fiktívne údaje)" (`civora:demo:proposal_to_contract[3]`, then retitled). Its one demo contract is `DEMO-2026-010`, "UKÁŽKA – …".

**Gotcha hit:** the processes block rendered **above** the hero in both orgs, because their hero blocks had `weight: nil` and Postgres sorts NULLs last. Fixed by hand on the stack (hero = 1, processes = 2). The task itself is fixed in civora-host#37.


### 2026-10-12 — puma starts by itself; Považská Bystrica data refresh

- **Why:** Docker restarted the app container on its own on 12. 10. (no `RestartCount`, fresh `StartedAt`). Puma had been started by hand, so the demo site stayed down until noticed.
- **Change:** new `Dockerfile.dev` → `civora-host:dev` (production image + git); the override runs it and starts puma (see the files below). Proved with `docker restart civora-host-app-1`: back to 200 in ~9 s, engine still mounted from `host-main`.
- **Backup:** `backups/pre-autostart-2026-10-12.dump`.
- **Data:** `bin/crz-first-sync 1 2026-10-04T00:00:00Z` → 2 new Považská Bystrica contracts (642 published CRZ mirrors); attachment backfill for them. 29 fictional `DEMO-*`/`MANUAL-*` records archived out of the public catalogue (list in the container at `/app/tmp/pb-archived-demo-refs.txt`); `DEMO-2026-010` kept and retitled "UKÁŽKA – …"; the demo process retitled "UKÁŽKA – Participatívny rozpočet (fiktívne údaje)"; the old "Demo: detske ihrisko" process unpublished.

## The uncommitted dev files

`Dockerfile.dev`:
```dockerfile
FROM civora-host:latest
USER root
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends git \
 && git config --system --add safe.directory '*' \
 && rm -rf /var/lib/apt/lists/*
USER rails
```

`docker-compose.override.yml`:
```yaml
services:
  app:
    build: !reset null
    image: civora-host:dev
    command: ["sh", "-c", "bundle install --local --quiet && exec bundle exec puma -C config/puma.rb"]
    environment:
      BUNDLE_DEPLOYMENT: "0"
      BUNDLE_FROZEN: "0"
      BUNDLE_LOCAL__DECIDIM_CONTRACTS_SK: /opt/decidim-contracts_sk
    volumes:
      - /Users/<you>/Code/decidim-contracts_sk:/opt/decidim-contracts_sk:ro
      - /Users/<you>/Code/decidim-app/Gemfile.dev-engine:/app/Gemfile:ro
```

`Gemfile.dev-engine`: generated from `Gemfile` in step 3.
