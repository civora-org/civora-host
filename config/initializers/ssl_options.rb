# frozen_string_literal: true

# TLS behind the terminator (docs/ops/tls.md, civora-org/civora-platform#168).
#
# Whether SSL is forced is decided by Decidim (DECIDIM_FORCE_SSL, see
# decidim_core.ssl_and_hsts); this file only shapes how Rack::SSL behaves when
# it is on. Caddy redirects plain HTTP at the edge, so the app never sees
# public plain traffic.
#
# The two health endpoints are exempt from the HTTP-to-HTTPS redirect: the
# compose healthcheck, the blackbox exporter and the deploy smoke test probe
# the app over the internal compose network on plain HTTP, where a redirect to
# https://app:3000 would make every probe fail. Exact paths only; both answer
# with a status document and nothing else, and are unreachable from outside
# on plain HTTP because Caddy redirects first.
health_paths = ["/up", "/healthz"].freeze

Rails.application.config.ssl_options = {
  redirect: { exclude: ->(request) { health_paths.include?(request.path) } },
  # One year, covering subdomains of the stack's own host. No preload: that is
  # a one-way commitment for a domain the municipality owns, not us.
  hsts: { expires: 1.year, subdomains: true, preload: false }
}
