# frozen_string_literal: true

require "test_helper"

# DECIDIM_FORCE_SSL=1 behind the TLS terminator (civora-org/civora-platform
# #168). The test environment does not force SSL, so the Rack::SSL middleware
# is built here from the app's real `ssl_options` (config/initializers/
# ssl_options.rb) and exercised directly.
class SslOptionsTest < ActiveSupport::TestCase
  INNER = ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }

  setup do
    @ssl = ActionDispatch::SSL.new(INNER, **Rails.application.config.ssl_options)
  end

  test "plain HTTP to a page is redirected to https" do
    status, headers, = @ssl.call(env("/sk/contracts", scheme: "http"))
    assert_equal 301, status
    assert_equal "https://zmluvy.example.sk/sk/contracts", headers["location"]
  end

  test "the health endpoints answer plain HTTP so internal probes keep working" do
    %w(/up /healthz).each do |path|
      status, = @ssl.call(env(path, scheme: "http"))
      assert_equal 200, status, path
    end
  end

  test "the exemption is exact: lookalike paths are still redirected" do
    ["/up/", "/upload", "/healthz.json", "/sk/up"].each do |path|
      status, = @ssl.call(env(path, scheme: "http"))
      assert_equal 301, status, path
    end
  end

  test "https responses carry HSTS for one year with subdomains and no preload" do
    _status, headers, = @ssl.call(env("/sk/contracts", scheme: "https"))
    hsts = headers["strict-transport-security"]
    assert_includes hsts, "max-age=31556952"
    assert_includes hsts, "includeSubDomains"
    assert_not_includes hsts, "preload"
  end

  test "a request the proxy marked https is not redirected and is treated as secure" do
    # Caddy terminates TLS and forwards plain HTTP with X-Forwarded-Proto: https.
    request_env = env("/sk/contracts", scheme: "http").merge("HTTP_X_FORWARDED_PROTO" => "https")
    status, headers, = @ssl.call(request_env)
    assert_equal 200, status
    assert headers["strict-transport-security"]
  end

  private

  # ActionDispatch::SSL reads the scheme from the Rack env; Rack::Request
  # resolves X-Forwarded-Proto into it.
  def env(path, scheme:)
    Rack::MockRequest.env_for("#{scheme}://zmluvy.example.sk#{path}")
  end
end
