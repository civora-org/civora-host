# Sourced by deploy.sh and smoke_test.sh (civora-org/civora-platform#168).
# POSIX sh. Decides which URL the stack answers on from the outside:
#
#   BASE_URL                  explicit override, wins
#   compose.tls.yml active    https://$SITE_ADDRESS  (Caddy is the only entry;
#                             the app's port 3000 is not published)
#   otherwise                 http://localhost:3000
#
# COMPOSE_FILE and SITE_ADDRESS come from the environment, else from .env
# (cron and fresh shells do not source it). Extra curl arguments go in
# CURL_OPTS, e.g. CURL_OPTS="--cacert caddy-root.crt" for the internal CA of a
# local *.localhost rehearsal; a real Let's Encrypt certificate needs none.

dotenv_value() {
  grep "^$1=" .env 2>/dev/null | tail -1 | cut -d= -f2- || true
}

stack_base_url() {
  if [ -n "${BASE_URL:-}" ]; then
    printf '%s' "$BASE_URL"
    return 0
  fi
  files="${COMPOSE_FILE:-$(dotenv_value COMPOSE_FILE)}"
  case ":$files:" in
    *compose.tls.yml:*)
      host="${SITE_ADDRESS:-$(dotenv_value SITE_ADDRESS)}"
      [ -n "$host" ] || { echo "SITE_ADDRESS is not set (compose.tls.yml is active)" >&2; return 1; }
      printf 'https://%s' "$host"
      ;;
    *) printf 'http://localhost:3000' ;;
  esac
}

# curl with the stack's CURL_OPTS (intentionally unquoted: a word list).
# shellcheck disable=SC2086
stack_curl() {
  curl ${CURL_OPTS:-} "$@"
}
