# frozen_string_literal: true

# Prometheus request metrics (civora-org/civora-platform#51).
#
# PrometheusExporter::Client.default reads PROMETHEUS_EXPORTER_HOST and
# PROMETHEUS_EXPORTER_PORT (see the gem's client.rb), so no client setup is
# needed here beyond registering the middleware. The middleware is registered
# only when a host is explicitly configured: without it, development and test
# never depend on a running exporter (the client sends asynchronously and
# swallows delivery errors, but there is no reason to activate it at all when
# unconfigured).
if ENV["PROMETHEUS_EXPORTER_HOST"].present?
  require "prometheus_exporter/middleware"

  # Reports per-request stats (status, durations) to the collector, which the
  # prometheus-exporter compose service exposes on /metrics for Prometheus.
  Rails.application.middleware.unshift PrometheusExporter::Middleware
end
