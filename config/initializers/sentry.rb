# frozen_string_literal: true

# Error tracking via Sentry protocol (civora-org/civora-platform#51).
# Self-hosted GlitchTip is Sentry-DSN compatible: point SENTRY_DSN at the
# GlitchTip project DSN. Disabled entirely when SENTRY_DSN is unset.
sentry_dsn = ENV.fetch("SENTRY_DSN", nil)

if sentry_dsn.present?
  Sentry.init do |config|
    config.dsn = sentry_dsn
    config.environment = Rails.env
    config.release = ENV.fetch("GIT_REVISION", nil)

    # Privacy: never attach request bodies, cookies, or user identifiers.
    config.send_default_pii = false
    config.before_send = lambda do |event, _hint|
      event.user = {} if event
      event.request.data = nil if event&.request
      event
    end
  end
end
