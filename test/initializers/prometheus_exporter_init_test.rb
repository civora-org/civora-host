# frozen_string_literal: true

require "test_helper"
require "prometheus_exporter/middleware"
require "prometheus_exporter/client"

# The Prometheus middleware is gated on an explicitly configured exporter
# host (config/initializers/prometheus_exporter.rb) so development and test
# never depend on a running collector. These tests pin that gate: with no
# PROMETHEUS_EXPORTER_HOST the middleware must stay unregistered, and the
# client resolves its target from the environment (documented gem behaviour,
# verified against prometheus_exporter 2.3.1 client.rb).
class PrometheusExporterInitTest < ActiveSupport::TestCase
  test "middleware is not registered when no exporter host is configured" do
    assert_not Rails.application.middleware.include?(PrometheusExporter::Middleware),
               "PrometheusExporter::Middleware must only be registered when PROMETHEUS_EXPORTER_HOST is set"
  end

  test "client falls back to localhost when no exporter host is configured" do
    with_exporter_host(nil) do
      client = PrometheusExporter::Client.new
      assert_equal "localhost", client.instance_variable_get(:@host)
    end
  end

  test "client honours a configured exporter host" do
    with_exporter_host("prometheus-exporter") do
      client = PrometheusExporter::Client.new
      assert_equal "prometheus-exporter", client.instance_variable_get(:@host)
    end
  end

  private

  def with_exporter_host(host)
    original = ENV.fetch("PROMETHEUS_EXPORTER_HOST", nil)
    if host.nil?
      ENV.delete("PROMETHEUS_EXPORTER_HOST")
    else
      ENV["PROMETHEUS_EXPORTER_HOST"] = host
    end
    yield
  ensure
    if original.nil?
      ENV.delete("PROMETHEUS_EXPORTER_HOST")
    else
      ENV["PROMETHEUS_EXPORTER_HOST"] = original
    end
  end
end
