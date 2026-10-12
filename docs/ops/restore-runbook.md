# Restore runbook

How to restore the Civora host app from a backup. Backup creation is `scripts/backup.sh` (Postgres dump + attachments tar + manifest + sha256), scheduled by cron; pruning is `scripts/backup_prune.sh` (7 daily / 4 weekly / 6 monthly).

**Policy gates:** a backup must be completed before every production deploy (`scripts/deploy.sh` enforces this); a restore drill is run quarterly and after any change to backup/restore scripts (`scripts/restore_drill.sh`, results in [restore-drill-log.md](restore-drill-log.md)).

**Targets:** RPO ≤ 24 h (nightly backup); RTO is measured by each drill.

## Preconditions

- Docker + Compose v2 on the target machine.
- The repo checked out at the image tag recorded in the backup's `manifest.json` (`image_tag`, `git_sha`) — schema must match the dump.
- `backups/<timestamp>/` present with: `db.dump`, `storage.tar.gz`, `manifest.json`, `sha256.txt`.
- **The backup's own `SECRET_KEY_BASE`.** `scripts/backup.sh` does not copy `.env`, and the dump holds data encrypted under that key (admin TOTP seeds, Decidim authorization metadata). Restore with a different key and the app boots, serves pages and passes row counts, but every enrolled admin is locked out at the second-factor challenge. Take the value from the secrets backup (password manager), not from the repo; if it is lost, the encrypted rows are unrecoverable and `bin/rails two_factor:reset_all REASON="secret_key_base lost"` is the only way back for admins (see [two-factor.md](two-factor.md)). Rotating the key after a suspected compromise is a separate step (see [secrets.md](secrets.md)).

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
- Decryption: `docker compose exec -T app ./bin/rails restore_drill:verify_encryption` decrypts a sample of TOTP seeds and authorization metadata and prints counts only (exit 0 = decrypted, 1 = could not decrypt, 3 = no encrypted rows). Exit 1 means the app is not running with the backup's `SECRET_KEY_BASE`. Do not hand the restored stack to users until it exits 0.

## Scheduled operation

Nightly backup + prune via host cron (03:15 `Europe/Bratislava`):

```cron
15 3 * * * cd /srv/civora-host && scripts/backup.sh >> log/backup.log 2>&1 && scripts/backup_prune.sh >> log/backup.log 2>&1
```

Backups contain internal/personal data — keep `backups/` at mode 0700 (backup.sh does this) and treat copies as secret material. Before real production data lands, add offsite replication + encryption (e.g. rclone to object storage, `age`/`BACKUP_ENCRYPT_KEY`).

## Restore drill (automated)

```bash
# The backup's SECRET_KEY_BASE comes from the secrets backup. Put it in a file
# only you can read (mode 0600, outside the repo, deleted afterwards) ...
DRILL_SECRET_KEY_BASE_FILE=/path/to/secret_key_base scripts/restore_drill.sh   # latest backup
# ... or pass backups/<timestamp>/ as the argument. DRILL_SECRET_KEY_BASE=<value> also works
# but leaves the value in your shell history; prefer the file.
```

Runs the entire runbook inside an isolated compose project (`civora-restore-drill`, never `civora-host`; the script refuses a `DRILL_PROJECT` that starts with `civora-host`; separate fresh volumes, throwaway DB password, ephemeral port, `--no-build` so it never touches the stack's image tags). The app boots with the **backup's own `SECRET_KEY_BASE`**; without one the script exits before starting anything, because a random key passes the HTTP and count checks yet cannot decrypt the backup (the failure mode of civora-org/civora-platform#196). It then:

1. restores the dump and attachments;
2. smoke-checks `/contracts` for HTTP 200;
3. runs `rake restore_drill:verify_encryption` in the app container: decrypts up to 50 TOTP credentials and 50 authorizations through Decidim's `AttributeEncryptor` (code in `app/lib/restore_drill/encryption_check.rb`, mounted from the checkout so an older image still gets it);
4. compares row counts with the manifest;
5. tears down and appends one row to [restore-drill-log.md](restore-drill-log.md).

| Result | Exit | Meaning |
|---|---|---|
| PASS | 0 | HTTP 200, counts match, at least one encrypted row decrypted and none failed |
| WARN | 2 | HTTP and counts fine, but the backup has no encrypted rows, so the key was **not** proven. Not a pass: re-run on a backup that has an enrolled admin |
| FAIL | 1 | HTTP, counts, or decrypt failed. A decrypt failure means the wrong `SECRET_KEY_BASE` |

The key is never printed: the script has no tracing, the check prints counts only, and the log row holds no key material. The drill container's environment holds the key while it runs (`docker inspect` on a throwaway project), and `down -v` removes it. Delete your key file afterwards.

## Troubleshooting

- **`pg_restore` version mismatch:** always run `pg_restore` inside the compose `db` container (postgres:17 client), never a host-installed client.
- **`schema_migrations` mismatch / errors on boot:** the repo checkout doesn't match `manifest.json.git_sha` — check out the recorded tag, or let `db:prepare` migrate forward only if the backup is newer than the schema.
- **Partial restore:** `--clean --if-exists` makes pg_restore re-runnable; re-run the same command, then re-run verification counts.
- **Attachments missing but DB fine:** the storage volume name depends on the compose project (`civora-host_app-storage`); verify with `docker volume ls`.
