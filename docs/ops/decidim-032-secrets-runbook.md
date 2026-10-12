# Decidim 0.32 secret-key and encryption upgrade runbook

Tracks [civora-org/civora-platform#187](https://github.com/civora-org/civora-platform/issues/187). Part of the Decidim 0.31 → 0.32 path in the engine's [upgrade spike](https://github.com/civora-org/decidim-contracts_sk/blob/main/docs/spikes/decidim-upgrade-path.md) (step 2, host branch on 0.32.1).

**Status: draft. The restore drill in section 7 has not been run.** Nothing in this document is a record of an executed upgrade or drill. The log in section 8 stays empty until a drill is actually executed and recorded.

This runbook covers only the secret and encryption side of the upgrade. The Gemfile, npm, Dockerfile, shakapacker and header-override work is in the host upgrade branch and is out of scope here.

## 1. What 0.32 changes about encryption and secrets

Sources are the upstream release notes for v0.32.0 (the release notes the issue points to) and the v0.32.1 source at tag `v0.32.1`. Quotes are verbatim.

**Release notes, v0.32.0**, [release page](https://github.com/decidim/decidim/releases/tag/v0.32.0):

1. On the Rails bump: "NOTE: Please note this release is updating Rails version from 7.2.2 to 8.1.2. Ensure you back up your `SECRET_KEY_BASE` env variable and also `tmp/local_secret.txt` if you have it."
2. On the encryption mechanism (release notes section 5.1): "As we have upgraded Rails from 7.0 we have improved the security of the application by upgrading the encryption mechanism from SHA1 to SHA256." and "All the previously encrypted attributes can be decoded, but on the next record change, the new data will be saved as SHA256. To manually upgrade authorization data, or the initiative votes metadata, you will need to run the below task." The task is `bin/rails decidim:upgrade:encryption`.

**Upstream source at v0.32.1:**

3. The key is derived from `SECRET_KEY_BASE`, and decryption falls back to the old SHA1 key. [`decidim-core/lib/decidim/attribute_encryptor.rb`](https://github.com/decidim/decidim/blob/v0.32.1/decidim-core/lib/decidim/attribute_encryptor.rb) builds the key with `ActiveSupport::KeyGenerator.new(secret, hash_digest_class:)` from `Rails.application.secret_key_base`. `decrypt` first tries the current digest and, on `InvalidMessage`, retries with a `legacy_encryptor` that uses `OpenSSL::Digest::SHA1`. So existing ciphertext keeps decrypting after the upgrade. Only a change of `SECRET_KEY_BASE` breaks it.
4. `decidim:upgrade:encryption` only re-saves Decidim's own encrypted records. The core task ([`decidim-core/lib/tasks/upgrade/decidim_encryption.rake`](https://github.com/decidim/decidim/blob/v0.32.1/decidim-core/lib/tasks/upgrade/decidim_encryption.rake)) runs `Decidim::Authorization.find_each(&:save)`. The initiatives module adds a second pass over `Decidim::InitiativesVote` ([`decidim-initiatives/.../decidim_encryption.rake`](https://github.com/decidim/decidim/blob/v0.32.1/decidim-initiatives/lib/tasks/initiatives/upgrade/decidim_encryption.rake)), which is chained onto the same task. Nothing else is touched. The task does not know about host-owned tables.
5. Where the production secret comes from. Rails 8.1.2 reads `secret_key_base` as `ENV["SECRET_KEY_BASE"]`, then `credentials.secret_key_base`. Only in local environments (development and test) does it fall back to generating `tmp/local_secret.txt` ([`railties/lib/rails/application/configuration.rb`](https://github.com/rails/rails/blob/v8.1.2/railties/lib/rails/application/configuration.rb), [`railties/lib/rails/application.rb`](https://github.com/rails/rails/blob/v8.1.2/railties/lib/rails/application.rb)). For this host, production means `SECRET_KEY_BASE` in `.env`. `tmp/local_secret.txt` matters only on a developer checkout.

What this means for the host:

- `config.load_defaults` moves from 7.2 to 8.1. The 8.1 defaults block in Rails 8.1.2 ([`configuration.rb`](https://github.com/rails/rails/blob/v8.1.2/railties/lib/rails/application/configuration.rb)) does not set any digest class. The SHA256 digest settings come from the 7.0 block, which the host already has. The keys derived from `SECRET_KEY_BASE` should therefore be the same before and after. This is verified from source only; the drill (section 7, step 6) is what proves it on the real data.
- The v0.32.1 release notes add a backport titled "Ensure JWT secret exists for `devise-jwt`" (decidim-api, [PR #17345](https://github.com/decidim/decidim/pull/17345)). It is not analysed here. Check it during the drill, because it concerns a secret.

## 2. What must be backed up first

Take all of these before any step in section 3 changes anything. Store the secrets in the password manager, not in the backup directory.

| Item | Where it lives | Why | How |
|---|---|---|---|
| `SECRET_KEY_BASE` | `.env` on the host (`SECRET_KEY_BASE=`) | Every key in section 4 is derived from it. A database dump without it cannot decrypt the encrypted data | Copy the value into the password manager entry for this stack. Do not paste it into chat, logs or this repo. Optional check: `printf %s "$SECRET_KEY_BASE" \| shasum -a 256 \| cut -c1-12` gives a fingerprint to write in the log |
| `tmp/local_secret.txt` | Developer checkouts only (`tmp/` in the repo root) | Release notes ask for it. Production does not read it (section 1, item 5) | Copy it with the password manager note for the checkout. Not needed for the production stack |
| `.env` | Host, `.env` (gitignored) | Holds `SECRET_KEY_BASE`, `POSTGRES_PASSWORD` and the rest of the inventory in [secrets.md](secrets.md) | Copy to the password manager as a file or as a secure note. Never into `backups/` |
| Database dump | `backups/<timestamp>/db.dump` | Rollback target, see section 6 | `scripts/backup.sh` (`pg_dump -Fc` inside the `db` container) |
| Attachments | `backups/<timestamp>/storage.tar.gz` | Rollback target; `data:migrate` can touch attachments | Same script |
| Manifest | `backups/<timestamp>/manifest.json` | Records `image_tag`, `git_sha` and row counts. Needed to rebuild the old image | Same script. Verify with `shasum -a 256 -c sha256.txt` before relying on it |

The backup does **not** contain `SECRET_KEY_BASE`. `scripts/backup.sh` does not copy `.env`. Losing the secret after a backup means losing the encrypted data that backup holds.

Treat the backup directory as secret material, as [restore-runbook.md](restore-runbook.md) already says. It is mode 0700.

## 3. Exact upgrade sequence

Run this only after the drill in section 7 has passed on a throwaway stack. Run it on the host from the upgrade branch with the new image built. The new image is `civora-host:latest` after `docker compose build app`.

The sequence is the issue's order (backup → deploy → migrate → encryption → data migrate → verify), with the one-off tasks from the v0.32.0 release notes (release notes sections 1.3 and 3) placed where the notes put them.

**Why the new image is not started with `up` before migrating.** `bin/docker-entrypoint` runs `./bin/rails db:prepare db:seed` on every `./bin/rails server` start. Starting the app first would migrate the database before the encryption task runs. The one-off commands below use `docker compose run --rm app <command>`, which bypasses that branch because the first argument is not `server`.

**Step 0. Maintenance window.** Announce it. Pilot users are not expected yet; still, nothing may write while the steps run.

```bash
docker compose stop app                       # no writes during the upgrade; db stays up
```

**Step 1. Backup and verify.**

```bash
scripts/backup.sh
cd backups/<timestamp> && shasum -a 256 -c sha256.txt && cat manifest.json && cd -
```

Confirm the secret and `.env` copies exist in the password manager. Do not continue without them.

**Step 2. Deploy the new image (code and config only, no migrations).** Build from the upgrade branch. Do not `up` the app yet.

```bash
docker compose build app
```

**Step 3. Gem-level upgrade tasks.**

```bash
docker compose run --rm app ./bin/rails decidim:upgrade
```

**Step 4. Schema.**

```bash
docker compose run --rm app ./bin/rails db:migrate
```

**Step 5. Encryption (the task this runbook is about).**

```bash
docker compose run --rm app ./bin/rails decidim:upgrade:encryption
```

It is idempotent. It re-saves Decidim's authorization records under the SHA256 digest (section 1, item 4). It does not change `SECRET_KEY_BASE`, and it does not touch the host's TOTP tables (section 4). Stop and go to section 7 on any exception. Do not rerun it blindly with a changed secret.

**Step 6. One-time data tasks from the release notes.**

```bash
docker compose run --rm app ./bin/rails decidim:upgrade:remove_deleted_users_left_data
docker compose run --rm app ./bin/rails decidim:upgrade:fix_deleted_members_follows
docker compose run --rm app ./bin/rails data:migrate
```

**Step 7. Start the app.** The entrypoint runs `db:prepare db:seed`, which is idempotent (see [restore-runbook.md](restore-runbook.md)).

```bash
docker compose up -d app
```

**Step 8. Verify.** Section 5.

Things that must not happen in this sequence:

- Do not change `SECRET_KEY_BASE` in `.env`. The upgrade does not need a new value.
- Do not run `two_factor:reset_all`. It is the rotation response, not an upgrade step. Running it here would force every admin to re-enrol for no reason.
- Do not skip step 5 because the data "looks fine". Records that are never re-saved stay on SHA1 indefinitely.

## 4. How the host's own encrypted data is affected

The host keeps three kinds of data that depend on `SECRET_KEY_BASE`.

**a. Admin TOTP seeds** (`civora_two_factor_credentials.otp_secret_ciphertext`). Written by `Decidim::AttributeEncryptor.encrypt` in [`app/models/two_factor/credential.rb`](../../app/models/two_factor/credential.rb). See [two-factor.md](two-factor.md).

- `decidim:upgrade:encryption` does **not** re-encrypt them. The core and initiatives tasks only touch Decidim's own models (section 1, item 4). The host's table is not in that list.
- They still decrypt after the upgrade. The read path is the same `Decidim::AttributeEncryptor.decrypt`, and a seed stored under the old SHA1 digest is still readable through the legacy fallback (section 1, item 3). So no action is needed for these rows during the upgrade.
- They are rewritten only when a credential is written again (a fresh enrolment or `two_factor:reset`). Their digest then follows the new default.
- They break only if `SECRET_KEY_BASE` changes. Then every enrolled factor is lost and `bin/rails two_factor:reset_all REASON="secret_key_base rotated"` is the only recovery (see [two-factor.md](two-factor.md)).

**b. Recovery-code digests** (`civora_two_factor_recovery_codes.code_digest`). An HMAC-SHA256 keyed from `Rails.application.key_generator.generate_key("civora two factor recovery codes", 32)` ([`app/models/two_factor/recovery_code.rb`](../../app/models/two_factor/recovery_code.rb)). This is not Decidim's encryptor, and the upgrade task does not touch it. It is derived from `SECRET_KEY_BASE` through Rails' key generator. Section 1 says the 8.1 defaults do not change the digest class for that generator. The drill must prove it: an unchanged recovery code must still be accepted after the upgrade.

**c. Decidim's own encrypted records.** Authorizations are re-saved by step 5. Any other Decidim encrypted attributes the host has (for example initiative votes, if `decidim-initiatives` is enabled in the Gemfile; it is commented out today) are handled by the same task chain.

Decidim also derives other values from `secret_key_base` (for example the forms `session_token` in a migration already in `db/migrate`). Those are not re-derived by the upgrade. Only a rotation changes them.

## 5. Verification checks

Run after step 7, in the order shown. Nothing here prints a secret.

```bash
# 5.1 The app serves and reports healthy.
curl -fsS http://localhost:3000/up
curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:3000/contracts      # expect 200

# 5.2 Migrations are current and no pending upgrade work remains.
docker compose exec app ./bin/rails db:migrate:status | grep -c '^\s*down' || true   # expect 0

# 5.3 Every TOTP seed still decrypts. Prints counts only.
docker compose exec app ./bin/rails runner '
  creds = TwoFactor::Credential.where.not(otp_secret_ciphertext: nil).to_a
  ok = creds.count { |c| begin; c.otp_secret.present?; rescue StandardError; false; end }
  puts "credentials=#{creds.size} decryptable=#{ok}"
'                                                                                  # expect decryptable == credentials

# 5.4 Enrolment state is what it was before the upgrade.
docker compose exec app ./bin/rails two_factor:status

# 5.5 Recovery codes still verify. Use a test code from the drill stack only; never a real recovery code.
#     Check on the drill: a code issued before the upgrade is accepted once after it.

# 5.6 Authorization records are readable and fully re-saved.
docker compose exec app ./bin/rails runner 'puts "authorizations=#{Decidim::Authorization.count}"'

# 5.7 No decryption errors in the logs since the restart.
docker compose logs --since 15m app 2>&1 | grep -i -E 'InvalidMessage|decrypt|secret' | head -20   # expect no output
```

Manual checks, on the drill stack and again on the host after the upgrade:

- Sign in as an enrolled admin with a current TOTP code. The challenge must accept it.
- Sign in with an unused recovery code from the pre-upgrade set (drill data only). It must be accepted once.
- Open the admin dashboard and one contract, and submit a no-op edit on a test record.
- Compare row counts with `manifest.json` → `row_counts` (see [restore-runbook.md](restore-runbook.md#verification)). Counts do not change through the upgrade except as migrations dictate.

## 6. Rollback

Decide quickly. Roll back if step 5 raises, if 5.3 shows any undecryptable credential, if 5.5 rejects a valid pre-upgrade recovery code, or if the app fails `/up`. Do not roll back on a cosmetic regression. Fix it forward.

The migrations move the schema forward only, so the rollback is a restore of the pre-upgrade database together with the old image. Do not run the new image against the old database.

```bash
# 1. Stop the app so nothing writes.
docker compose stop app

# 2. Check out the git SHA recorded in the pre-upgrade manifest, and rebuild the old image.
#    Use the manifest's git_sha, not a guess.
git -C . checkout <manifest git_sha>
docker compose build app

# 3. Restore the database and attachments exactly as in restore-runbook.md.
cat backups/<timestamp>/db.dump | docker compose exec -T db pg_restore -U postgres -d decidim_app_production --no-owner --no-privileges --clean --if-exists
docker run --rm -v civora-host_app-storage:/dst -v "$PWD/backups/<timestamp>":/src:ro alpine sh -c "tar xzf /src/storage.tar.gz -C /dst"

# 4. Secrets: SECRET_KEY_BASE must be the same value. Check the fingerprint against the log.
#    If .env was edited during the upgrade, restore the value from the password manager.

# 5. Start the old image and verify.
docker compose up -d app
```

After the rollback, run the checks in section 5.1, 5.3 and 5.4. Counts must match the manifest. Record the rollback in section 8 and in the incident log if it happened in production.

## 7. Restore drill checklist

Run once on a throwaway stack **before any pilot data exists**. Use fictional data only. This is the drill the issue asks for. It is not optional, and the first real upgrade must not be the first time this procedure runs.

Use a separate compose project (`compose.drill.yml`, project name `civora-restore-drill`) with fresh volumes, so the dev and demo databases are not touched. Do not run it against the live demo stack.

**Drill caveat, read before starting.** `scripts/restore_drill.sh` generates a random `DRILL_KEYBASE` for the app container (see [`compose.drill.yml`](../../compose.drill.yml) and the script). A backup restored with a different `SECRET_KEY_BASE` will not decrypt its TOTP seeds, and the script's HTTP 200 and row-count checks will still pass. The script therefore does not prove the encryption path. This drill must start the restored stack with the **same** `SECRET_KEY_BASE` that wrote the backup. Either run these steps by hand, or extend the script to take `DRILL_KEYBASE` from the environment in a separate change.

Checklist:

- [ ] **1. Fictional seed.** On the throwaway stack from the current 0.31.7 image, create one admin with fictional e-mail, enrol its TOTP, and save the ten recovery codes in the drill notes. Create one authorization record through the normal flow with fictional data. No real persons, no real codes.
- [ ] **2. Pre-upgrade backup.** `scripts/backup.sh` on the drill stack. Verify with `shasum -a 256 -c`. Record the timestamp.
- [ ] **3. Secret fingerprint.** Record the first 12 hex of the SHA-256 of the drill `SECRET_KEY_BASE` in section 8. Store the drill value in the drill password-manager entry.
- [ ] **4. Upgrade on the drill stack** with the sequence in section 3, steps 0–7. Keep the output of each step.
- [ ] **5. Verify.** Run section 5.1–5.7 and the manual checks. Record the TOTP decryptable count and the recovery code result.
- [ ] **6. Same-secret restore.** Bring up a second, fresh drill project from the pre-upgrade backup with the **same** `SECRET_KEY_BASE`. Run the section 5.3 check. It must show `decryptable == credentials`. This confirms the backup round-trips the secret-dependent data.
- [ ] **7. Wrong-secret negative test.** Repeat step 6 with a different `SECRET_KEY_BASE`. Section 5.3 must show that the seeds do **not** decrypt, and the TOTP sign-in must fail. Then run `bin/rails two_factor:reset_all REASON="drill: wrong secret"` and confirm the admin is asked to re-enrol. This proves the warning in section 4 is real and that the documented recovery works.
- [ ] **8. Rollback.** From the upgraded drill stack, run section 6 with the pre-upgrade backup and the pre-upgrade git SHA. Verify counts against the manifest.
- [ ] **9. Timing and log.** Record the wall-clock duration of the upgrade steps and the restore, and fill in section 8.
- [ ] **10. Tear down.** `docker compose -p civora-restore-drill down -v`. Confirm the drill `.env` and drill backup are removed or kept only in the password manager, not in the repo.

If any step fails, fix the procedure first, then rerun the whole drill. A partial pass is not a pass.

## 8. Drill log

One row per executed drill. Fill it in only after the drill has actually run. The table is empty by design: no drill has been run for this document.

| Date (UTC) | Operator | Image and git SHA (pre / post) | Backup timestamp | `SECRET_KEY_BASE` fingerprint (first 12 hex) | TOTP decryptable (credentials / decryptable) | Recovery code accepted after upgrade | Wrong-secret negative test | Rollback verified | Duration (upgrade / restore) | Result | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| _not run_ | | | | | | | | | | | |

Result values: `PASS`, `FAIL`, or `PARTIAL` (state which step). Notes must not contain secret values, real names or real e-mail addresses.

## 9. Related

- [secrets.md](secrets.md): policy and inventory. Rotation procedure.
- [two-factor.md](two-factor.md): admin TOTP, `two_factor:reset_all`.
- [restore-runbook.md](restore-runbook.md): backup and restore, `scripts/restore_drill.sh`.
- [restore-drill-log.md](restore-drill-log.md): log of the automated restore drill.
- Engine upgrade spike: [`docs/spikes/decidim-upgrade-path.md`](https://github.com/civora-org/decidim-contracts_sk/blob/main/docs/spikes/decidim-upgrade-path.md) in `civora-org/decidim-contracts_sk`.
