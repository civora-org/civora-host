# Restore runbook

How to restore the Civora host app from a backup. Backup creation is `scripts/backup.sh` (Postgres dump + attachments tar + manifest + sha256), scheduled by cron; pruning is `scripts/backup_prune.sh` (7 daily / 4 weekly / 6 monthly).

**Policy gates:** a backup must be completed before every production deploy (`scripts/deploy.sh` enforces this); a restore drill is run quarterly and after any change to backup/restore scripts (`scripts/restore_drill.sh`, results in [restore-drill-log.md](restore-drill-log.md)).

**Targets:** RPO ≤ 24 h (nightly backup); RTO is measured by each drill.

## Preconditions

- Docker + Compose v2 on the target machine.
- The repo checked out at the image tag recorded in the backup's `manifest.json` (`image_tag`, `git_sha`) — schema must match the dump.
- `backups/<timestamp>/` present with: `db.dump`, `storage.tar.gz`, `manifest.json`, `sha256.txt`.
- Secrets available (`.env`): `SECRET_KEY_BASE` may stay the same, but rotating it after a suspected compromise is part of incident response (see [secrets.md](secrets.md)).

## Verify the backup first

```bash
cd backups/<timestamp> && shasum -a 256 -c sha256.txt
cat manifest.json
```

If checksums fail, do **not** restore from this copy — fall back to the previous backup or the offsite copy.

## Restore steps

```bash
# 1. (Optional) stop the app so nothing writes during restore:
docker compose stop app

# 2. Restore the database (db service stays up).
#    pg_restore runs inside the postgres:17 container — same major as prod.
cat backups/<timestamp>/db.dump | \
  docker compose exec -T db createdb -U postgres --template=fresh 2>/dev/null || true
#    For an in-place restore into the existing DB:
cat backups/<timestamp>/db.dump | \
  docker compose exec -T db pg_restore -U postgres -d decidim_app_production \
    --no-owner --no-privileges --clean --if-exists

# 3. Restore attachments into the storage volume:
docker run --rm -v civora-host_app-storage:/dst -v "$PWD/backups/<timestamp>":/src:ro \
  alpine sh -c "tar xzf /src/storage.tar.gz -C /dst"

# 4. Start the app. The entrypoint runs db:prepare + seed; both are idempotent
#    (the seed find_or_create_by!'s the organization by host — no duplicates).
docker compose up -d app
```

## Verification

Compare against `manifest.json` → `row_counts`:

```bash
docker compose exec -T db psql -U postgres -d decidim_app_production -Atc "
  SELECT 'organizations=' || count(*) FROM decidim_organizations
  UNION ALL SELECT 'users=' || count(*) FROM decidim_users
  UNION ALL SELECT 'attachments=' || count(*) FROM active_storage_attachments
  UNION ALL SELECT 'blobs=' || count(*) FROM active_storage_blobs;"
```

- Counts match the manifest (organizations = 1, blobs/attachments match pre-backup state).
- Attachment files present: blob count in DB == files under the `app-storage` volume (`docker run --rm civora-host_app-storage:... find /dst -type f | wc -l`).
- Freshness: `MAX(created_at)` on key tables is consistent with the backup timestamp (no post-backup data expected — that window is the accepted RPO loss).
- Smoke: `curl -fsS http://localhost:3000/contracts` → 200; admin sign-in works.

## Scheduled operation

Nightly backup + prune via host cron (03:15 `Europe/Bratislava`):

```cron
15 3 * * * cd /srv/civora-host && scripts/backup.sh >> log/backup.log 2>&1 && scripts/backup_prune.sh >> log/backup.log 2>&1
```

Backups contain internal/personal data — keep `backups/` at mode 0700 (backup.sh does this) and treat copies as secret material. Before real production data lands, add offsite replication + encryption (e.g. rclone to object storage, `age`/`BACKUP_ENCRYPT_KEY`).

## Restore drill (automated)

```bash
scripts/restore_drill.sh            # latest backup; or pass backups/<timestamp>/
```

Runs the entire runbook inside an isolated compose project (separate project name, fresh volumes, throwaway secrets, ephemeral port), verifies counts against the manifest plus HTTP 200, tears down, and appends one row to [restore-drill-log.md](restore-drill-log.md). Exit code 0 = PASS.

## Troubleshooting

- **`pg_restore` version mismatch:** always run `pg_restore` inside the compose `db` container (postgres:17 client), never a host-installed client.
- **`schema_migrations` mismatch / errors on boot:** the repo checkout doesn't match `manifest.json.git_sha` — check out the recorded tag, or let `db:prepare` migrate forward only if the backup is newer than the schema.
- **Partial restore:** `--clean --if-exists` makes pg_restore re-runnable; re-run the same command, then re-run verification counts.
- **Attachments missing but DB fine:** the storage volume name depends on the compose project (`civora-host_app-storage`); verify with `docker volume ls`.
