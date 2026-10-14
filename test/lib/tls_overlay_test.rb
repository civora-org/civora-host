# frozen_string_literal: true

require "test_helper"

# Structural, offline pin of the TLS terminator overlay (compose.tls.yml,
# deploy/caddy/Caddyfile) against docs/ops/tls.md (civora-org/civora-platform
# #168). Whether Caddy really issues certificates and redirects needs the
# Docker stack; the manual rehearsal in the doc covers that. This suite guards
# the settings the pilot relies on from drifting.
class TlsOverlayTest < ActiveSupport::TestCase
  OVERLAY = Rails.root.join("compose.tls.yml").freeze
  BASE = Rails.root.join("compose.yaml").freeze
  CADDYFILE = Rails.root.join("deploy/caddy/Caddyfile").freeze
  DOC = Rails.root.join("docs/ops/tls.md").freeze

  test "the overlay forces SSL in the app and unpublishes plain port 3000" do
    app = overlay.dig("services", "app")
    assert_equal "1", app.dig("environment", "DECIDIM_FORCE_SSL")
    # `!reset []` is a YAML tag; psych drops tags, so assert on the source too.
    assert_match(/ports: !reset \[\]/, OVERLAY.read)
    assert_equal "0", base.dig("services", "app", "environment", "DECIDIM_FORCE_SSL"),
                 "the base file keeps the plain-HTTP local default; the overlay is what turns SSL on"
  end

  test "caddy is the only published entry, on 80 and 443" do
    caddy = overlay.dig("services", "caddy")
    assert_equal ["80:80", "443:443", "443:443/udp"], caddy["ports"]
    assert_equal "service_healthy", caddy.dig("depends_on", "app", "condition")
    assert caddy["healthcheck"], "caddy needs a healthcheck so `up --wait` and ps show a dead terminator"
  end

  test "caddy image is pinned to a minor version, not a floating major" do
    assert_match(/\Acaddy:\d+\.\d+\z/, overlay.dig("services", "caddy", "image"))
  end

  test "site address and acme contact are required, not defaulted" do
    env = overlay.dig("services", "caddy", "environment")
    assert_match(/\$\{SITE_ADDRESS:\?/, env["SITE_ADDRESS"])
    assert_match(/\$\{ACME_EMAIL:\?/, env["ACME_EMAIL"])
  end

  test "caddyfile proxies the whole site to the app and sets no client-controlled trust" do
    file = CADDYFILE.read.lines.grep_v(/\A\s*#/).join
    assert_includes file, "{$SITE_ADDRESS}"
    assert_includes file, "reverse_proxy app:3000"
    assert_no_match(/trusted_proxies/, file, "trusting client X-Forwarded-* would let a client spoof its IP and scheme")
  end

  test "the doc names every variable the overlay needs" do
    doc = DOC.read
    %w(SITE_ADDRESS ACME_EMAIL DECIDIM_ORG_HOST DECIDIM_FORCE_SSL COMPOSE_FILE).each do |name|
      assert_includes doc, name
    end
  end

  private

  def overlay = @overlay ||= YAML.safe_load_file(OVERLAY, aliases: true)

  def base = @base ||= YAML.safe_load_file(BASE, aliases: true)
end
