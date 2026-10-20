# Restore runbook

How backups are made, kept and restored for the Civora host app. Backup creation is `scripts/backup.sh` (Postgres dump + attachments tar + manifest + sha256, encrypted with `age`, copied to an S3-compatible off-site target), scheduled by cron; retention is `scripts/backup_prune.sh` (30 days, local and off-site).

**Policy gates:** a backup must be completed before every production deploy (`scripts/deploy.sh` enforces this); a restore drill from the **off-site copy** is run quarterly and after any change to backup/restore scripts (`scripts/restore_drill.sh --offsite`, results in [restore-drill-log.md](restore-drill-log.md)).

**Targets:** RPO ≤ 24 h (nightly backup); RTO is measured by each drill.

## What the DPA promises, and what implements it

The DPA template's annex 1 (civora-platform `docs/06-sales/dpa-zoou-template.sk.md`, *Zálohy*) promises backups that are daily, encrypted, stored off the server and separately from production, kept for a target of 30 days, with a restore test once per quarter, and deleted after the retention period. This is the mapping, so the wording and the stack stay one thing (civora-org/civora-platform#167, ADR-011 decision 4):

| Annex 1 says | Implemented by | Proof |
|---|---|---|
| denné (daily) | cron 03:15 `Europe/Bratislava`, `BackupStale` alert after 26 h | [observability.md](observability.md) |
| šifrované (encrypted) | `age`, public-key recipients in `BACKUP_AGE_RECIPIENTS`; dump and attachments are piped through age, **no plaintext file ever exists on the server**; the private key is never on the server ([secrets.md](secrets.md#backup-encryption-key-age)) | `BACKUP_STRICT=1` makes plaintext impossible; first off-site drill in [restore-drill-log.md](restore-drill-log.md) |
| uložené mimo servera a oddelene od produkcie (off the server, separate from production) | `scripts/backup_offsite.sh`: upload to an S3-compatible bucket at a **different provider or account** than the server, verified against the local copy, `OffsiteBackupStale` alert after 26 h | the drill restores from the bucket alone, on a machine that has none of the server's files |
| cieľová retencia 30 dní (30-day retention) | `BACKUP_RETENTION_DAYS=30`, local and off-site, no weekly or monthly tiers | `scripts/backup_prune.sh`; unit tests in `test/lib/backup_scripts_test.rb` |
| raz za štvrťrok skúška obnovy (quarterly restore test) | `scripts/restore_drill.sh --offsite` | [restore-drill-log.md](restore-drill-log.md) |
| vymazanie zálohy po uplynutí retencie (deletion after retention) | the same prune; the newest backup is the only exception | a copy lives at most 30 days plus the time to the next nightly prune |

Wording to use in the annex once the pilot server runs this (replaces the "Zavedie sa pred spustením pilotu" marker and the open "konečnú potvrdíme" clause): *Zálohy: denné, šifrované (age, kľúč mimo servera), uložené mimo servera u iného poskytovateľa než produkcia; retencia 30 dní, potom sa zmažú; raz za štvrťrok overená obnova z externej kópie.* If a contract needs another retention, it is a per-stack setting (`BACKUP_RETENTION_DAYS`), not a code change.

## Preconditions

- Docker + Compose v2 on the target machine.
- The repo checked out at the image tag recorded in the backup's `manifest.json` (`image_tag`, `git_sha`) — schema must match the dump.
- `backups/<timestamp>/` present with: `db.dump.age`, `storage.tar.gz.age`, `manifest.json`, `sha256.txt` (older or unencrypted backups: `db.dump`, `storage.tar.gz` instead). Not on this machine any more? Fetch it from the off-site target first (below).
- **The age private key** for an encrypted backup: `BACKUP_AGE_IDENTITY_FILE=/path/to/key` on the machine you restore from. Without it the backup is unreadable by design; see [secrets.md](secrets.md#backup-encryption-key-age).
- **The backup's own `SECRET_KEY_BASE`.** `scripts/backup.sh` does not copy `.env`, and the dump holds data encrypted under that key (admin TOTP seeds, Decidim authorization metadata). Restore with a different key and the app boots, serves pages and passes row counts, but every enrolled admin is locked out at the second-factor challenge. Take the value from the secrets backup (password manager), not from the repo; if it is lost, the encrypted rows are unrecoverable and `bin/rails two_factor:reset_all REASON="secret_key_base lost"` is the only way back for admins (see [two-factor.md](two-factor.md)). Rotating the key after a suspected compromise is a separate step (see [secrets.md](secrets.md)).
- **The backup's own Active Record Encryption keys** (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`, plus `ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS` if the backup predates a rotation). The contract templates' personal data (`personal_values`) is encrypted under them, and the app **refuses to boot in production without them**. Take them from the secrets backup, in the same password-manager entry as `SECRET_KEY_BASE`. A restore with other keys boots, but the personal data is unreadable and cannot be recovered; if the keys are lost, that data is gone ([secrets.md](secrets.md#active-record-encryption-keys)).

## Verify the backup first

```bash
cd backups/<timestamp> && shasum -a 256 -c sha256.txt
cat manifest.json
```

If checksums fail, do **not** restore from this copy — fall back to the previous backup or the off-site copy. (The checksums cover the stored, encrypted files; `age` is authenticated encryption, so a corrupted file also fails to decrypt instead of restoring garbage.)

## Restore from the off-site copy

The server is gone, or its disk is. Everything needed is the bucket credentials, the age private key and a checkout of this repository on a machine with Docker:

```bash
# 1. The off-site settings (.env, or the environment): BACKUP_OFFSITE_BUCKET, _PREFIX,
#    _ENDPOINT, _REGION, _PROVIDER, _ACCESS_KEY_ID, _SECRET_ACCESS_KEY.
# 2. Download the newest complete backup (or name one: scripts/backup_fetch.sh 20261014T031500Z).
#    It stays encrypted; the sha256 of every file is verified.
scripts/backup_fetch.sh latest backups
# 3. Decrypt on a machine you trust (plaintext personal data: delete it afterwards).
BACKUP_AGE_IDENTITY_FILE=/path/to/age.key scripts/backup_decrypt.sh backups/<timestamp> /secure/dir/restore
# 4. Continue with "Restore steps" below, using /secure/dir/restore/db.dump and
#    /secure/dir/restore/storage.tar.gz in place of backups/<timestamp>/ ...
```

`scripts/backup_fetch.sh latest` ignores an upload that has no `manifest.json` (an interrupted upload; the manifest is uploaded last). A drill does steps 2 and 3 as a stream with no plaintext on disk: `scripts/restore_drill.sh --offsite`.

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
- Smoke: `curl -fsSL http://localhost:3000/contracts` → 200; admin sign-in works.
- Decryption: `docker compose exec -T app ./bin/rails restore_drill:verify_encryption` decrypts a sample of TOTP seeds and authorization metadata and prints counts only (exit 0 = decrypted, 1 = could not decrypt, 3 = no encrypted rows). It also reads the `personal_values` of up to 50 contract template entries when the installed engine has them. Exit 1 means the app is not running with the backup's `SECRET_KEY_BASE` or Active Record Encryption keys. Do not hand the restored stack to users until it exits 0.

## Scheduled operation

Nightly backup, off-site copy and prune via host cron (03:15 `Europe/Bratislava`):

```cron
15 3 * * * cd /srv/civora-host && scripts/backup.sh >> log/backup.log 2>&1 && scripts/backup_prune.sh >> log/backup.log 2>&1
```

`backup.sh` calls `backup_offsite.sh` itself, so one command produces a verified encrypted local and off-site backup and the two dead-man pings. Cron does not source `.env`: the scripts read the `BACKUP_*` variables and `PUSHGATEWAY_URL` from `.env` on their own (an exported variable wins).

If `backup.sh` fails, `&&` skips the prune on purpose. A failing night leaves the previous copies in place and an alert after 26 h (`BackupStale` or `OffsiteBackupStale`); it never prunes the last good copy either (the newest backup is exempt from retention).

## Configuration

Set in `.env` (template in [`.env.example`](../../.env.example)); `BACKUP_STRICT=1` is the pilot setting:

| Variable | Meaning |
|---|---|
| `BACKUP_AGE_RECIPIENTS` | One or more age **public** keys, space or comma separated. Use at least two: the operator's key and an escrow key kept elsewhere, so losing one key does not lose every backup |
| `BACKUP_STRICT` | `1`: `backup.sh` refuses to run without recipients and without an off-site target, and refuses to upload plaintext. Set it on every stack with real data |
| `BACKUP_RETENTION_DAYS` | Default `30`, local and off-site |
| `BACKUP_OFFSITE_BUCKET` | Bucket on an S3-compatible service; setting it turns the off-site copy on. Create the bucket once at the provider |
| `BACKUP_OFFSITE_PREFIX` | Folder per stack/city inside the bucket, default `civora`. One prefix per municipality keeps restore and deletion per city |
| `BACKUP_OFFSITE_ENDPOINT` | Provider's S3 endpoint URL; empty for AWS S3 |
| `BACKUP_OFFSITE_REGION` | Region, where the provider needs one |
| `BACKUP_OFFSITE_PROVIDER` | rclone S3 flavour, default `Other`; `AWS`, `Minio`, `Cloudflare`, `Scaleway` and others change small protocol details |
| `BACKUP_OFFSITE_ACCESS_KEY_ID`, `BACKUP_OFFSITE_SECRET_ACCESS_KEY` | A key limited to that bucket (list, read, write; delete only if the script prunes) |
| `BACKUP_OFFSITE_PRUNE` | `0`: the script never deletes remote objects; use a bucket lifecycle rule (expire after 30 days) and a key without delete permission |
| `BACKUP_TOOLS_IMAGE` | Image with `age` and `rclone`, used when the host has neither. Default `civora-backup-tools:1`, built on first use from `deploy/backup-tools` (the only host requirement is Docker). A host `age` or `rclone` on `PATH` is used as is |
| `BACKUP_TOOLS_DOCKER_ARGS` | Extra `docker run` arguments for that image, for instance `--network` in a local rehearsal |
| `BACKUP_AGE_IDENTITY_FILE` | **Restore time only**, on your machine: path to the age private key. Never set on the server |

Choosing the target: a bucket at a **different provider or account** than the server, in the EU, so one provider outage or one stolen account does not take production and the backups together. Turn on object versioning or object lock if the provider offers it: the server's key can then overwrite but not destroy history. The data in the bucket is ciphertext, so the provider is not a processor of the content; the annex's sub-processor list still names it (annex 2).

Backups contain internal and personal data. Even encrypted, keep `backups/` at mode 0700 (`backup.sh` does this) and the bucket private.

## Restore drill (automated)

```bash
# The backup's SECRET_KEY_BASE comes from the secrets backup. Put it in a file
# only you can read (mode 0600, outside the repo, deleted afterwards).
# The age private key is a file on your machine as well.
export DRILL_SECRET_KEY_BASE_FILE=/path/to/secret_key_base
# The backup's Active Record Encryption keys, from the same password-manager entry (one value per file):
export DRILL_AR_PRIMARY_KEY_FILE=/path/to/ar_primary_key
export DRILL_AR_SALT_FILE=/path/to/ar_key_derivation_salt
# only for a backup older than a key rotation: DRILL_AR_PREVIOUS_KEYS_FILE=/path/to/old_primary_keys (comma-separated)
export BACKUP_AGE_IDENTITY_FILE=/path/to/age.key

scripts/restore_drill.sh --offsite             # the real path: download the newest backup from the bucket, drill it
scripts/restore_drill.sh --offsite 20261014T031500Z
scripts/restore_drill.sh                        # newest local backups/<timestamp>/
scripts/restore_drill.sh backups/<timestamp>    # a specific local one
# DRILL_SECRET_KEY_BASE=<value> also works but leaves the value in your shell history; prefer the file.
```

Quarterly drills use `--offsite`, from a machine that is **not** the production server: that proves the copy in the bucket, the key and the procedure rather than the server's own disk. The first drill with the real pilot data runs on a second machine (a "fresh VM") before the pilot goes live.

Runs the entire runbook inside an isolated compose project (`civora-restore-drill`, never `civora-host`; the script refuses a `DRILL_PROJECT` that starts with `civora-host`; separate fresh volumes, throwaway DB password, ephemeral port, `--no-build` so it never touches the stack's image tags). The app boots with the **backup's own `SECRET_KEY_BASE` and Active Record Encryption keys**; without them the script exits before starting anything, because a random key passes the HTTP and count checks yet cannot decrypt the backup (the failure mode of civora-org/civora-platform#196). It then:

0. with `--offsite`, downloads the backup and verifies its checksums (any mismatch stops the drill);
1. restores the dump and attachments (an encrypted backup is decrypted as a stream, so no plaintext lands on disk);
2. smoke-checks `/contracts` for HTTP 200;
3. runs `rake restore_drill:verify_encryption` in the app container: decrypts up to 50 TOTP credentials and 50 authorizations through Decidim's `AttributeEncryptor`, and up to 50 contract template entries' `personal_values` through Active Record Encryption (code in `app/lib/restore_drill/encryption_check.rb`, mounted from the checkout so an older image still gets it);
4. compares row counts with the manifest;
5. tears down and appends one row to [restore-drill-log.md](restore-drill-log.md).

| Result | Exit | Meaning |
|---|---|---|
| PASS | 0 | HTTP 200, counts match, at least one encrypted row decrypted and none failed |
| WARN | 2 | HTTP and counts fine, but the backup has no encrypted rows, so the key was **not** proven. Not a pass: re-run on a backup that has an enrolled admin |
| FAIL | 1 | HTTP, counts, or decrypt failed. A decrypt failure means the wrong `SECRET_KEY_BASE` or encryption keys |

A drill that fails before it can write a row (wrong age key, checksum mismatch, bucket unreachable) exits non-zero and appends nothing; the terminal output is the record, and a real failure is noted in the log's narrative.

The key is never printed: the script has no tracing, the check prints counts only, and the log row holds no key material. The drill container's environment holds the key while it runs (`docker inspect` on a throwaway project), and `down -v` removes it. Delete your key file afterwards.

## Local rehearsal (no server, no provider)

The whole chain runs on a laptop against a throwaway stack and a local S3 server, which is how the scripts were first verified (civora-org/civora-platform#167). Use a **separate project name** so the real `civora-host` stack is never touched, and a different port:

```bash
# throwaway stack (.env gets COMPOSE_PROJECT_NAME=civora-test-bk and fresh secrets; publish the app on a spare port)
docker compose up -d --no-build
# local S3: any S3 server works; this one is MinIO (the official minio/minio images are no longer
# published, bitnamilegacy/minio:2025.7.23 is the last one that is still pullable; a rehearsal image only)
docker run -d --name civora-test-minio -p 127.0.0.1:19000:9000 \
  -e MINIO_ROOT_USER=<throwaway-user> -e MINIO_ROOT_PASSWORD=<throwaway-secret> bitnamilegacy/minio:2025.7.23
# keys: generate two with `age-keygen` (host binary, or: docker run --rm civora-backup-tools:1 age-keygen)
export BACKUP_AGE_RECIPIENTS="<public key 1> <public key 2>" BACKUP_STRICT=1 \
  BACKUP_OFFSITE_BUCKET=civora-backups-test BACKUP_OFFSITE_PREFIX=civora/city-test \
  BACKUP_OFFSITE_ENDPOINT=http://host.docker.internal:19000 BACKUP_OFFSITE_PROVIDER=Minio \
  BACKUP_OFFSITE_ACCESS_KEY_ID=<throwaway-user> BACKUP_OFFSITE_SECRET_ACCESS_KEY=<throwaway-secret>
# once: create the bucket (the normal key is not expected to be allowed to)
RCLONE_CONFIG_OFFSITE_NO_CHECK_BUCKET=false sh -c '. scripts/lib/backup_env.sh; backup_env_load; backup_rclone mkdir offsite:$BACKUP_OFFSITE_BUCKET'
scripts/backup.sh                                   # encrypted, uploaded, verified
rm -rf backups                                      # nothing local: the bucket is the only copy
DRILL_PROJECT=civora-test-bk-drill PORT=3198 DRILL_SECRET_KEY_BASE_FILE=... DRILL_AR_PRIMARY_KEY_FILE=... DRILL_AR_SALT_FILE=... BACKUP_AGE_IDENTITY_FILE=... \
  scripts/restore_drill.sh --offsite
```

Tear it all down afterwards (`docker compose down -v`, `docker rm -f civora-test-minio`, delete the key files). On Linux, `host.docker.internal` needs `BACKUP_TOOLS_DOCKER_ARGS="--add-host=host.docker.internal:host-gateway"`.

## Troubleshooting

- **`age: error: no identity matched any of the recipients`:** the key is not one of the backup's recipients (the manifest does not list them; try the escrow key). Nothing else can decrypt it.
- **`Checksum mismatch` on fetch:** the object in the bucket changed or was truncated. Fetch the previous backup; do not restore from this one.
- **Upload fails with `NoSuchBucket` or `AccessDenied`:** the bucket does not exist or the key lacks permission. `backup.sh` exits non-zero with the local backup intact; fix and run `scripts/backup_offsite.sh backups/<timestamp>` to upload it late.
- **`pg_restore` version mismatch:** always run `pg_restore` inside the compose `db` container (postgres:17 client), never a host-installed client.
- **`schema_migrations` mismatch / errors on boot:** the repo checkout doesn't match `manifest.json.git_sha` — check out the recorded tag, or let `db:prepare` migrate forward only if the backup is newer than the schema.
- **Partial restore:** `--clean --if-exists` makes pg_restore re-runnable; re-run the same command, then re-run verification counts.
- **Attachments missing but DB fine:** the storage volume name depends on the compose project (`civora-host_app-storage`); verify with `docker volume ls`.
