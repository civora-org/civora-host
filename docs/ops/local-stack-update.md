# Updating the local dev stack

How to move the local Docker stack (the one used for sales demos) to newer host and engine code. Each run is recorded in the [update log](#update-log) at the end.

This is **not** a production deploy. There is no production host yet; for a server, see [demo-server.md](demo-server.md).

## How the local stack is put together

| Part | Where the code comes from | How it changes |
|---|---|---|
| Host app (`civora-host`) | **Baked into the Docker image** `civora-host:latest` | `git pull` + `docker compose build app` |
| Engine (`decidim-contracts_sk`) | **Mounted** from the engine repo's worktree `.claude/worktrees/host-main` (read-only bind mount at `/opt/decidim-contracts_sk`) | `git checkout` in that worktree + puma restart |
| Gemfile inside the container | `Gemfile.dev-engine` (uncommitted, bind-mounted over `/app/Gemfile`): a copy of `Gemfile` with the engine line switched to `path:` | Regenerate whenever `Gemfile` changes |
| Dev overrides | `docker-compose.override.yml` (uncommitted): `command: sleep infinity`, the mounts above, `BUNDLE_FROZEN=0` | Rarely |
| Database | Postgres volume, database `decidim_app_production` | Migrations |

Two uncommitted files make this work: `Gemfile.dev-engine` and `docker-compose.override.yml`. Don't delete them, and don't commit them.

Because of `command: sleep infinity`, **puma does not start by itself**. You start it by hand (step 8).

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

5. **Rebuild the image and recreate the containers.** The build takes 2–5 minutes.
   ```bash
   docker compose build app
   docker compose up -d app scheduler
   ```

6. **Install git in the container and resolve the bundle.** The image has no `git`, but the engine's gemspec runs `git ls-files` when it is loaded from a path. This is a dev-only workaround; production installs the engine as a git gem.
   ```bash
   docker exec -u root civora-host-app-1 sh -c 'apt-get update -qq && apt-get install -y -qq git && git config --system --add safe.directory "*"'
   docker exec civora-host-app-1 sh -c 'cd /app && bundle install --local'
   ```
   Check that the bundle uses the mounted engine:
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

8. **Start puma.**
   ```bash
   docker exec -d civora-host-app-1 sh -c 'cd /app && bundle exec puma -C config/puma.rb > /app/log/puma.out 2>&1'
   ```
   To restart it later:
   ```bash
   docker exec civora-host-app-1 pkill -f puma
   ```
   Then run the start command again.

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
