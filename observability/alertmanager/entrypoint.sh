#!/bin/sh
# Render the Alertmanager config template from env (.env via compose) and
# start Alertmanager. Runs under the image's busybox sh.
#
# Unset values get inert defaults so the stack still boots unconfigured:
# deliveries then fail and are logged (see alertmanager.yml header).
set -eu

# Without SMTP credentials, point at an inert local smarthost instead of
# Gmail, so no anonymous/failed logins ever reach a real mail provider.
if [ -n "${ALERT_SMTP_USERNAME:-}" ]; then
  DEFAULT_SMARTHOST=smtp.gmail.com:587
else
  DEFAULT_SMARTHOST=127.0.0.1:25
fi

TEMPLATE=/etc/alertmanager/alertmanager.yml.tmpl
CONFIG=/tmp/alertmanager.yml

# Escape sed replacement specials ('\', '&', and the '|' delimiter).
esc() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }

sed \
  -e "s|__ALERT_TELEGRAM_BOT_TOKEN__|$(esc "${ALERT_TELEGRAM_BOT_TOKEN:-unset}")|g" \
  -e "s|__ALERT_TELEGRAM_CHAT_ID__|$(esc "${ALERT_TELEGRAM_CHAT_ID:-1}")|g" \
  -e "s|__ALERT_EMAIL_TO__|$(esc "${ALERT_EMAIL_TO:-root@localhost}")|g" \
  -e "s|__ALERT_EMAIL_FROM__|$(esc "${ALERT_EMAIL_FROM:-${ALERT_SMTP_USERNAME:-alertmanager@localhost}}")|g" \
  -e "s|__ALERT_SMTP_SMARTHOST__|$(esc "${ALERT_SMTP_SMARTHOST:-$DEFAULT_SMARTHOST}")|g" \
  -e "s|__ALERT_SMTP_USERNAME__|$(esc "${ALERT_SMTP_USERNAME:-}")|g" \
  -e "s|__ALERT_SMTP_PASSWORD__|$(esc "${ALERT_SMTP_PASSWORD:-}")|g" \
  "$TEMPLATE" > "$CONFIG"
chmod 600 "$CONFIG"

exec /bin/alertmanager --config.file="$CONFIG" --storage.path=/alertmanager
