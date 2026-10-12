# Restore drill log

One row per executed drill (`scripts/restore_drill.sh`). Policy: quarterly and after any change to backup/restore scripts. Duration = wall-clock of the drill (start DB → verified app), in seconds. sha256 = first 12 hex of the restored backup's `db.dump` checksum. Decrypt = whether the app, booted with the backup's own `SECRET_KEY_BASE`, decrypted encrypted rows (`decrypted`, `FAILED`, or `none (warning)` when the backup had no encrypted rows; a warning is not a pass). Result = PASS, WARN (exit 2) or FAIL.

The two oldest rows predate civora-org/civora-platform#196. Those drills booted with a random `SECRET_KEY_BASE`, so their PASS says nothing about whether the encrypted rows (admin TOTP seeds, authorizations) could be decrypted. Do not cite them as proof that a restore keeps admins able to sign in. The next drill on a real backup, with the real key from the secrets backup, replaces that evidence.

**Validation of the #196 change (not a real-backup drill).** On 2026-10-12 the changed script was run end to end against a throwaway backup, built from a throwaway database on its own compose project (one fictional admin with a TOTP credential and one authorization; no real data, no production key). Right key: PASS, `decrypted two_factor_credentials=1 authorizations=1`, exit 0. Wrong key (same backup): FAIL, `could not decrypt two_factor_credentials=1 authorizations=1`, exit 1, although HTTP 200 and the row counts still matched. These runs are not in the table because they did not exercise a real backup.

## Drills

New rows are appended below by the script; keep this table last.

| Date (UTC) | Duration | Backup | db.dump sha256 | HTTP | Decrypt | Result |
|---|---|---|---|---|---|---|
| 2026-09-02T20:47:07Z | 18s | 20260902T204656Z | f0735a3bb432 | 200 | not checked | PASS (random key, see above) |
| 2026-10-03T08:50:12Z | 21s | 20261003T085011Z | 4b24a1e1cae2 | 200 | not checked | PASS (random key, see above) |
