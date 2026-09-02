# Restore drill log

One row per executed drill (`scripts/restore_drill.sh`). Policy: quarterly and after any change to backup/restore scripts. Duration = wall-clock of the drill (start DB → verified app), in seconds. sha256 = first 12 hex of the restored backup's `db.dump` checksum.

| Date (UTC) | Duration | Backup | db.dump sha256 | HTTP | Result |
|---|---|---|---|---|---|
| 2026-09-02T20:47:07Z | 18s | 20260902T204656Z | f0735a3bb432 | 200 | PASS |
