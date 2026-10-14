# Retention rule shared by the local and the off-site prune
# (civora-org/civora-platform#167). POSIX sh, sourced.
#
# A backup is identified by its UTC timestamp name YYYYmmddTHHMMSSZ. It expires
# once it is BACKUP_RETENTION_DAYS (default 30) old; nothing is kept in weekly
# or monthly tiers, because the DPA promises that backups are gone after the
# retention period. The newest backup is never expired, so a stretch of failed
# backups cannot prune the last good copy.

# backup_stamp_epoch STAMP -> epoch seconds, or 0 when STAMP is not a stamp.
backup_stamp_epoch() {
  case "$1" in
    ????????T??????Z) ;;
    *) echo 0; return 0 ;;
  esac
  d="${1%%T*}"; t="${1#*T}"; t="${t%Z}"
  # BSD date (macOS) first, then GNU date (Linux).
  date -u -j -f "%Y%m%d%H%M%S" "$d$t" +%s 2>/dev/null \
    || date -u -d "$(printf '%s' "$d" | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/') $(printf '%s' "$t" | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/')" +%s 2>/dev/null \
    || echo 0
}

# stdin: stamps, one per line (anything else is ignored).
# stdout: the stamps to delete. Honors BACKUP_RETENTION_DAYS and BACKUP_NOW_EPOCH.
backup_expired_stamps() {
  now="${BACKUP_NOW_EPOCH:-$(date -u +%s)}"
  limit=$(( ${BACKUP_RETENTION_DAYS:-30} * 86400 ))
  # `|| [ -n "$stamp" ]` keeps a last line that has no trailing newline.
  valid="$(while read -r stamp || [ -n "$stamp" ]; do
    [ "$(backup_stamp_epoch "$stamp")" -gt 0 ] && printf '%s\n' "$stamp"
  done | sort)"
  newest="$(printf '%s\n' "$valid" | tail -1)"
  printf '%s\n' "$valid" | while read -r stamp; do
    [ -n "$stamp" ] || continue
    [ "$stamp" != "$newest" ] || continue
    age=$(( now - $(backup_stamp_epoch "$stamp") ))
    [ "$age" -lt "$limit" ] || printf '%s\n' "$stamp"
  done
}
