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
| `SECRET_KEY_BASE` | Rails session/cookie signing | `.env` (dev & prod) | rotate → invalidates sessions **and every enrolled admin second factor**: run `two_factor:reset_all` right after ([two-factor.md](two-factor.md)). **Not in `backups/`:** keep a copy in the password manager; the restore drill needs it ([restore-runbook.md](restore-runbook.md)) |
| `POSTGRES_PASSWORD` | Postgres auth (compose + `database.yml`) | `.env` | dev compose overlay uses trust auth instead |
| `DATABASE_USERNAME` / `DATABASE_PASSWORD` | `config/database.yml` | `.env` (prod), unset locally | local dev uses peer auth |
| `DATABASE_URL` | `config/database.yml` (production block) | unset | only if moving to a URL-style DB config |
| `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_AUTHENTICATION` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_DOMAIN` | production mailer (`config/environments/production.rb`) | **unset — production mail is not configured yet** | wire at first real deploy; see `.env.example` |
| `ALERT_TELEGRAM_BOT_TOKEN` / `ALERT_SMTP_PASSWORD` (+ non-secret `ALERT_TELEGRAM_CHAT_ID`, `ALERT_EMAIL_TO`, `ALERT_SMTP_USERNAME`) | Alertmanager delivery (`observability/alertmanager/entrypoint.sh`) | `.env` | SMTP password is a Google app password; rotate the bot token via `@BotFather` → `/revoke` |
| `GITHUB_TOKEN` | Docker build (engine gem fetch), optional: only for private forks | `.env` | passed as BuildKit **secret mount**, never a build arg; not in image layers |
| `ENGINE_READ_TOKEN` | CI (engine checkout; a leftover from the private period, removable together with the workflow's `insteadOf` steps) | GitHub Actions secret | fine-grained PAT, Contents: read on the engine repo |
| `STORAGE_PROVIDER` + `AWS_*` / `GCS_*` / `AZURE_*` | `config/storage.yml` | unset | dormant, only if Active Storage moves to object storage. Unrelated to the backup target below |
| `BACKUP_AGE_RECIPIENTS` | `scripts/backup.sh` | `.env` | age **public** keys: not secret, and not sensitive if leaked. The matching private keys are the secret, see [Backup encryption key](#backup-encryption-key-age) |
| `BACKUP_OFFSITE_ACCESS_KEY_ID` / `BACKUP_OFFSITE_SECRET_ACCESS_KEY` | `scripts/backup_offsite.sh`, `backup_prune.sh` | `.env` | S3 key limited to the backup bucket, one per stack. Passed to rclone through the environment, never on a command line or in a config file. Rotate at the provider and in `.env` together; a leaked key exposes ciphertext only, but can delete backups unless the bucket has versioning, object lock or a delete-less key (`BACKUP_OFFSITE_PRUNE=0`) |
| age **private** key (`BACKUP_AGE_IDENTITY_FILE` at restore time) | `scripts/restore_drill.sh`, `backup_decrypt.sh` | operator's password manager + an offline copy; **never on the server, never in `.env`** | decrypts every backup it is a recipient of |
| `REDIS_URL`, `PORT`, `RAILS_MAX_THREADS`, `RAILS_LOG_*`, `RAILS_ASSET_HOST`, `DECIDIM_ORG_HOST` (seeded organization host, `db/seeds.rb`) | config (not secret) | compose / env | listed for completeness |
| OmniAuth / Maps / Etherpad / VAPID families | future `config/initializers/decidim.rb` | — | not in the surface yet; will arrive via `Decidim::Env` when the initializer lands |

Secrets are never shared between environments (see [environments.md](environments.md)).

**Decidim 0.32 upgrade:** `SECRET_KEY_BASE` must stay unchanged; the upgrade's encryption step (`decidim:upgrade:encryption`) re-encrypts only Decidim's own records. Back up the secret before the upgrade and never rotate it as a side effect. See [decidim-032-secrets-runbook.md](decidim-032-secrets-runbook.md).

## Backup encryption key (age)

Backups are encrypted with [age](https://age-encryption.org) to public-key recipients (civora-org/civora-platform#167). The server holds only the **public** keys (`BACKUP_AGE_RECIPIENTS`), which can encrypt and cannot decrypt. That is the point: a stolen server, disk or bucket yields ciphertext only. The price is that the private key is the one thing that stands between you and an unrecoverable backup, so its custody is a procedure, not an afterthought.

**Generate** on the operator's own machine, never on the server: `age-keygen -o civora-backup-<city>.key` (or `docker run --rm civora-backup-tools:1 age-keygen`, after the first script run has built the image). The file contains the private key and, in a comment, the public key (`age1...`) that goes into `BACKUP_AGE_RECIPIENTS`.

**Keep at least two recipients**, each with its own private key in a different place:

| Key | Held by | Where |
|---|---|---|
| Operator key | the maintainer, used for drills and restores | password manager entry (attachment or secure note) |
| Escrow key | kept apart from the operator key | offline: printed or on an encrypted USB drive in a safe place, and handed to the second person once one exists ([incident-response.md](incident-response.md) names the backup maintainer). Not on any machine that is online with the operator key |

One lost key then costs nothing, and losing both makes every backup unreadable; there is no recovery. Test the escrow key too: every quarterly drill decrypts once with the operator key, and a second drill per year uses the escrow key.

**Per stack or shared.** One key pair per municipality limits a compromise to that city and keeps deletion per city clean; the cost is more keys to look after. At the pilot (one city) it is one pair. Do not reuse a key pair between a stack with real data and a demo or test stack.

**Never next to the backup it opens.** The key does not go in the bucket, in the repository, in `.env` on the server, or in the same password-manager entry as the bucket credentials. The restore also needs the stack's `SECRET_KEY_BASE` (separate entry, see the inventory above): the age key opens the backup, `SECRET_KEY_BASE` opens the data inside it that Rails encrypted (admin TOTP seeds).

**Rotation.** To retire a key, add the new public key to `BACKUP_AGE_RECIPIENTS` and remove the old one. New backups use the new set from the next night. Old backups still need the old key until they age out of the 30-day window; keep the old key until then, then destroy it. A rotation is also what to do if a private key may have leaked.

**If a private key is compromised or lost.** Leaked: assume every backup in the bucket for the last 30 days is readable by the finder if they also have bucket access. Treat it as a possible personal-data breach ([incident-response.md](incident-response.md)), rotate as above and rotate the bucket key too. Lost (one of two): add a replacement recipient now. Lost (both): backups are gone; start a fresh backup chain immediately and tell the municipality, because the recovery point is gone.

**Rehearse it.** Custody that has never been exercised is a guess: the restore drill (`scripts/restore_drill.sh --offsite`) is how the operator proves they can find the key, the bucket credentials and `SECRET_KEY_BASE` and bring a stack up.

## Handling rules

- Do not paste secret values into logs, issue comments, docs, or chat. Docs and examples use placeholders only.
- Backups contain internal data and must be treated as secret material, even though they are encrypted: see the [restore runbook](restore-runbook.md).
- Rotation triggers: suspected leak, contributor offboarding with repo/Actions access, or at minimum annually.
