# Shared helpers for the backup scripts (civora-org/civora-platform#167,
# docs/ops/restore-runbook.md). POSIX sh, meant to be sourced from the
# repository root by backup.sh, backup_offsite.sh, backup_fetch.sh,
# backup_decrypt.sh, backup_prune.sh and restore_drill.sh.
#
# Configuration comes from the environment, else from .env (cron does not
# source it). The list is exactly the BACKUP_* surface plus the pushgateway:
#
#   BACKUP_AGE_RECIPIENTS      age public key(s), space or comma separated.
#                              Encrypts every backup. The private key is NEVER
#                              on this machine (docs/ops/secrets.md)
#   BACKUP_STRICT              1 = refuse to run unless encryption AND the
#                              off-site target are configured (pilot posture)
#   BACKUP_RETENTION_DAYS      default 30, local and off-site
#   BACKUP_OFFSITE_BUCKET      S3-compatible bucket; setting it turns the
#   BACKUP_OFFSITE_PREFIX      off-site copy on. Prefix per stack/city
#   BACKUP_OFFSITE_ENDPOINT    (default "civora"), empty endpoint = AWS S3
#   BACKUP_OFFSITE_REGION
#   BACKUP_OFFSITE_PROVIDER    rclone s3 provider, default "Other"
#   BACKUP_OFFSITE_ACCESS_KEY_ID / BACKUP_OFFSITE_SECRET_ACCESS_KEY
#   BACKUP_OFFSITE_PRUNE       0 = leave remote expiry to a bucket lifecycle rule
#   BACKUP_TOOLS_IMAGE         image with age and rclone, used when the host
#                              has none (built from deploy/backup-tools)
#   BACKUP_TOOLS_DOCKER_ARGS   extra `docker run` arguments for that image
#                              (e.g. --network for a local MinIO rehearsal)
#   PUSHGATEWAY_URL            dead-man pings (docs/ops/observability.md)
#
# Restore time only (operator's machine, never the server):
#   BACKUP_AGE_IDENTITY_FILE   path to the age private key

backup_dotenv_get() {
  # Last assignment wins; surrounding single or double quotes are stripped.
  v="$(grep "^$1=" .env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

backup_env_load() {
  for name in BACKUP_AGE_RECIPIENTS BACKUP_STRICT BACKUP_RETENTION_DAYS \
    BACKUP_OFFSITE_BUCKET BACKUP_OFFSITE_PREFIX BACKUP_OFFSITE_ENDPOINT \
    BACKUP_OFFSITE_REGION BACKUP_OFFSITE_PROVIDER BACKUP_OFFSITE_ACCESS_KEY_ID \
    BACKUP_OFFSITE_SECRET_ACCESS_KEY BACKUP_OFFSITE_PRUNE BACKUP_TOOLS_IMAGE \
    BACKUP_TOOLS_DOCKER_ARGS PUSHGATEWAY_URL; do
    eval "current=\${$name:-}"
    if [ -z "$current" ]; then
      value="$(backup_dotenv_get "$name")"
      [ -z "$value" ] || export "$name=$value"
    fi
  done
  BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
  export BACKUP_RETENTION_DAYS
}

backup_encryption_configured() { [ -n "$(printf '%s' "${BACKUP_AGE_RECIPIENTS:-}" | tr -d ', ')" ]; }
backup_offsite_configured() { [ -n "${BACKUP_OFFSITE_BUCKET:-}" ]; }

# --- tools: host binary when present, else the tools image -------------------

backup_tools_image() { printf '%s' "${BACKUP_TOOLS_IMAGE:-civora-backup-tools:1}"; }

backup_ensure_tools_image() {
  img="$(backup_tools_image)"
  docker image inspect "$img" >/dev/null 2>&1 && return 0
  [ -d deploy/backup-tools ] || { echo "Cannot build $img: deploy/backup-tools is missing" >&2; return 1; }
  echo "==> Building $img (age + rclone)" >&2
  docker build -q -t "$img" deploy/backup-tools >/dev/null
}

# age recipients as "-r KEY" arguments (word list, public keys only).
backup_age_recipient_args() {
  for key in $(printf '%s' "${BACKUP_AGE_RECIPIENTS:-}" | tr ',' ' '); do
    printf -- '-r %s ' "$key"
  done
}

# stdin -> stdout. Needs only the public recipients.
backup_age_encrypt() {
  if command -v age >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    age $(backup_age_recipient_args)
  else
    backup_ensure_tools_image || return 1
    # shellcheck disable=SC2046
    docker run --rm -i "$(backup_tools_image)" age $(backup_age_recipient_args)
  fi
}

# stdin -> stdout. $1 = identity (private key) file on this machine.
backup_age_decrypt() {
  [ -r "$1" ] || { echo "age identity file is not readable: $1" >&2; return 1; }
  if command -v age >/dev/null 2>&1; then
    age -d -i "$1"
  else
    backup_ensure_tools_image || return 1
    docker run --rm -i -v "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")":/identity:ro \
      "$(backup_tools_image)" age -d -i /identity
  fi
}

# --- rclone ------------------------------------------------------------------

# The remote "offsite" is defined entirely through RCLONE_CONFIG_OFFSITE_* env
# variables: no config file with credentials on disk. Credentials reach a
# containerized rclone by NAME (docker -e NAME), never as a command-line value.
backup_rclone_export() {
  export RCLONE_CONFIG_OFFSITE_TYPE=s3
  export RCLONE_CONFIG_OFFSITE_PROVIDER="${BACKUP_OFFSITE_PROVIDER:-Other}"
  export RCLONE_CONFIG_OFFSITE_ENV_AUTH=false
  export RCLONE_CONFIG_OFFSITE_ENDPOINT="${BACKUP_OFFSITE_ENDPOINT:-}"
  export RCLONE_CONFIG_OFFSITE_REGION="${BACKUP_OFFSITE_REGION:-}"
  export RCLONE_CONFIG_OFFSITE_ACCESS_KEY_ID="${BACKUP_OFFSITE_ACCESS_KEY_ID:-}"
  export RCLONE_CONFIG_OFFSITE_SECRET_ACCESS_KEY="${BACKUP_OFFSITE_SECRET_ACCESS_KEY:-}"
  # A key limited to the bucket cannot create it; the bucket exists already
  # (create it once at the provider, docs/ops/restore-runbook.md).
  export RCLONE_CONFIG_OFFSITE_NO_CHECK_BUCKET="${RCLONE_CONFIG_OFFSITE_NO_CHECK_BUCKET:-true}"
  # No config file is used; keep rclone's "config not found" notice out of cron mail.
  export RCLONE_LOG_LEVEL="${RCLONE_LOG_LEVEL:-ERROR}"
}

# offsite:<bucket>/<prefix>  (no trailing slash)
backup_remote_base() {
  prefix="${BACKUP_OFFSITE_PREFIX:-civora}"
  prefix="${prefix#/}"; prefix="${prefix%/}"
  printf 'offsite:%s/%s' "$BACKUP_OFFSITE_BUCKET" "$prefix"
}

backup_rclone_env_flags() {
  for n in $(env | sed -n 's/^\(RCLONE_[A-Z0-9_]*\)=.*/\1/p'); do printf -- '-e %s ' "$n"; done
}

# backup_rclone ARGS...: rclone with no local files involved (lsf, purge, ...).
backup_rclone() {
  backup_rclone_export
  if command -v rclone >/dev/null 2>&1; then
    rclone "$@"
  else
    backup_ensure_tools_image || return 1
    # shellcheck disable=SC2046
    docker run --rm $(backup_rclone_env_flags) ${BACKUP_TOOLS_DOCKER_ARGS:-} \
      "$(backup_tools_image)" rclone "$@"
  fi
}

# backup_rclone_local MODE DIR ARGS...: rclone with a host directory. The token
# @LOCAL@ in ARGS becomes DIR on the host, or /local (mounted, MODE ro|rw)
# inside the image.
backup_rclone_local() {
  mode="$1"; dir="$2"; shift 2
  backup_rclone_export
  if command -v rclone >/dev/null 2>&1; then
    localpath="$dir"
  else
    backup_ensure_tools_image || return 1
    localpath=/local
  fi
  count=$#
  while [ "$count" -gt 0 ]; do
    arg="$1"; shift
    [ "$arg" != "@LOCAL@" ] || arg="$localpath"
    set -- "$@" "$arg"
    count=$((count - 1))
  done
  if [ "$localpath" = "$dir" ]; then
    rclone "$@"
  else
    # shellcheck disable=SC2046
    docker run --rm $(backup_rclone_env_flags) ${BACKUP_TOOLS_DOCKER_ARGS:-} \
      -v "$(cd "$dir" && pwd)":/local:"$mode" "$(backup_tools_image)" rclone "$@"
  fi
}

# --- pushgateway (non-fatal) -------------------------------------------------

# backup_push_gauge NAME VALUE: POST to the civora-backup group. POST replaces
# only the metric of that name, so the local and the off-site ping coexist.
backup_push_gauge() {
  [ -n "${PUSHGATEWAY_URL:-}" ] || return 2
  printf '%s %s\n' "$1" "$2" \
    | curl -fsS --max-time 10 --data-binary @- "$PUSHGATEWAY_URL/metrics/job/civora-backup" >/dev/null
}
