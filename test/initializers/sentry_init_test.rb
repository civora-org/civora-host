# frozen_string_literal: true

require "test_helper"
require "sentry/test_helper"

# Pins the config/initializers/sentry.rb contract: a strict no-op unless
# SENTRY_DSN is configured (development/tests never depend on a collector),
# and privacy hardening when it is. The initializer is `load`-ed against a
# controlled environment so the tests exercise the real file.
class SentryInitTest < ActiveSupport::TestCase
  INITIALIZER = Rails.root.join("config/initializers/sentry.rb")

  test "SDK is uninitialized in test env (initializer is a no-op without SENTRY_DSN)" do
    skip "SENTRY_DSN is set on this machine" if ENV["SENTRY_DSN"].present?
    assert_not Sentry.initialized?,
               "sentry.rb must not initialise the SDK when SENTRY_DSN is unset"
  end

  test "initializer initialises the SDK with privacy hardening when SENTRY_DSN is set" do
    with_dsn(Sentry::TestHelper::DUMMY_DSN) do
      load INITIALIZER.to_s
      assert Sentry.initialized?, "sentry.rb must initialise the SDK when SENTRY_DSN is set"
      assert_equal false, Sentry.configuration.send_default_pii
      assert_equal Rails.env, Sentry.configuration.environment
    end
  end

  test "before_send is registered as a callable that strips user and request data" do
    with_dsn(Sentry::TestHelper::DUMMY_DSN) do
      load INITIALIZER.to_s
      hook = Sentry.configuration.before_send
      assert_kind_of Proc, hook,
                     "before_send must be assigned (writer form), not passed as a discarded block"

      event = Sentry::Event.new(configuration: Sentry.configuration)
      event.user = { email: "someone@example.com", ip_address: "10.0.0.1" }
      result = hook.call(event, nil)
      assert_same event, result, "before_send must return the event to keep delivery"
      assert_empty result.user, "user scope must be stripped before delivery"
    end
  end

  private

  def with_dsn(dsn)
    original = ENV.fetch("SENTRY_DSN", nil)
    ENV["SENTRY_DSN"] = dsn
    yield
  ensure
    if original.nil?
      ENV.delete("SENTRY_DSN")
    else
      ENV["SENTRY_DSN"] = original
    end
    Sentry.close if Sentry.initialized?
  end
end
