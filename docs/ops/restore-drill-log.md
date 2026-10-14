# Restore drill log

One row per executed drill (`scripts/restore_drill.sh`). Policy: quarterly and after any change to backup/restore scripts. Duration = wall-clock of the drill (start DB → verified app), in seconds. sha256 = first 12 hex of the restored backup's `db.dump` checksum. Decrypt = whether the app, booted with the backup's own `SECRET_KEY_BASE`, decrypted encrypted rows (`decrypted`, `FAILED`, or `none (warning)` when the backup had no encrypted rows; a warning is not a pass). Result = PASS, WARN (exit 2) or FAIL.

The two oldest rows predate civora-org/civora-platform#196. Those drills booted with a random `SECRET_KEY_BASE`, so their PASS says nothing about whether the encrypted rows (admin TOTP seeds, authorizations) could be decrypted. Do not cite them as proof that a restore keeps admins able to sign in. The next drill on a real backup, with the real key from the secrets backup, replaces that evidence.

**Validation of the #196 change (not a real-backup drill).** On 2026-10-12 the changed script was run end to end against a throwaway backup, built from a throwaway database on its own compose project (one fictional admin with a TOTP credential and one authorization; no real data, no production key). Right key: PASS, `decrypted two_factor_credentials=1 authorizations=1`, exit 0. Wrong key (same backup): FAIL, `could not decrypt two_factor_credentials=1 authorizations=1`, exit 1, although HTTP 200 and the row counts still matched. These runs are not in the table because they did not exercise a real backup.

**First real-backup drill with the backup's own key (civora-org/civora-platform#187).** On 2026-10-14 the drill restored a backup of the local demo stack, taken just before its Decidim 0.31.7 to 0.32.1 upgrade (3 organizations, 7 users, 2 enrolled admins). The app was booted from the 0.32.1 image (`civora-host:latest`) with the key taken from that stack's own environment. The restored 0.31 schema was migrated forward by the entrypoint (`db:prepare data:migrate db:seed`), and the two TOTP seeds, written under the 0.31 key derivation, decrypted: `decrypted two_factor_credentials=2`. The backup had no Decidim authorizations, so only TOTP seeds were exercised. This row replaces the two random-key rows above as evidence that a restore keeps admins able to sign in.

**First drill from the off-site encrypted copy (civora-org/civora-platform#167).** On 2026-10-14 a throwaway stack (own compose project, fictional data: one admin with a TOTP credential, one attachment file) was backed up with `scripts/backup.sh` and `BACKUP_STRICT=1`: dump and attachments encrypted with age (two recipients), uploaded to a local MinIO bucket, verified. The local `backups/` directory was then removed, so the bucket held the only copy, and `scripts/restore_drill.sh --offsite` downloaded it, verified the checksums, decrypted as a stream with the operator key and restored into a second throwaway project booted with the backup's own `SECRET_KEY_BASE`: HTTP 200, row counts equal to the manifest, `decrypted two_factor_credentials=1`. Negative checks in the same session: a key that is not a recipient fails the drill at the restore step ("no identity matched any of the recipients"); a tampered object in the bucket is rejected by the checksum on fetch; the escrow key decrypts the same backup; a failed upload exits non-zero with the local backup intact and pushes no off-site ping. The target was a local S3 server on the same machine, not a second provider, and the "fresh VM" was a second compose project, so the drill on real infrastructure (a second machine, the real provider) is still to be run before the pilot holds real data. This row is the evidence for the scripts, not for a provider.

## Drills

New rows are appended below by the script; keep this table last.

| Date (UTC) | Duration | Backup | db.dump sha256 | HTTP | Decrypt | Result |
|---|---|---|---|---|---|---|
| 2026-09-02T20:47:07Z | 18s | 20260902T204656Z | f0735a3bb432 | 200 | not checked | PASS (random key, see above) |
| 2026-10-03T08:50:12Z | 21s | 20261003T085011Z | 4b24a1e1cae2 | 200 | not checked | PASS (random key, see above) |
| 2026-10-14T17:48:49Z | 23s | 20261014T173952Z | 2baba3dc107e | 200 | decrypted | PASS |
| 2026-10-14T19:27:34Z | 24s | 20261014T192710Z (encrypted) (off-site) | d981093fc7c0 | 200 | decrypted | PASS |
