# frozen_string_literal: true

require "test_helper"

# Pins the claims made in docs/ops/log-policy.md against the actual
# configuration: Docker log rotation in compose.yaml, Rails parameter
# filtering (app list + Decidim's additions), and the host logrotate snippet.
class LogPolicyTest < ActiveSupport::TestCase
  test "compose.yaml caps app/db/redis json-file logs exactly as documented" do
    compose = YAML.safe_load_file(Rails.root.join("compose.yaml"))
    {
      "app" => %w(10m 5),
      "db" => %w(10m 3),
      "redis" => %w(10m 3)
    }.each do |service, (max_size, max_file)|
      options = compose.dig("services", service, "logging", "options")
      assert_equal "json-file", compose.dig("services", service, "logging", "driver"), service
      assert_equal max_size, options["max-size"], service
      assert_equal max_file, options["max-file"], service
    end
  end

  test "observability overlay caps every service's json-file logs as documented" do
    overlay = YAML.safe_load_file(Rails.root.join("compose.observability.yml"), aliases: true)
    # "app" is only a merge fragment here — its caps (10m × 5) come from
    # compose.yaml and are pinned by the test above.
    services = overlay["services"].except("app")
    assert_equal(
      %w(alertmanager blackbox-exporter glitchtip glitchtip-db glitchtip-worker
         prometheus prometheus-exporter pushgateway),
      services.keys.sort
    )
    services.each do |service, config|
      options = config.dig("logging", "options") || {}
      max_file = service == "alertmanager" ? "2" : "3"
      assert_equal "json-file", config.dig("logging", "driver"), service
      assert_equal "10m", options["max-size"], service
      assert_equal max_file, options["max-file"], service
    end
  end

  test "filter_parameters matches the documented privacy list" do
    # Rails may keep the raw symbol list or the compiled Regexp depending on
    # when it is inspected; normalise both to searchable strings.
    compiled = Rails.application.config.filter_parameters
    source = compiled.is_a?(Regexp) ? compiled.source : Array(compiled).map(&:to_s).join("|")
    %w(passw email secret token _key crypt salt certificate otp ssn).each do |param|
      assert_includes source, param, "documented app filter missing: #{param}"
    end
    %w(document_number postal_code mobile_phone_number).each do |param|
      assert_includes source, param, "Decidim filter missing: #{param}"
    end
  end

  test "logrotate.conf matches the documented schedule (weekly, 12 rotations, compress)" do
    conf = Rails.root.join("docs/ops/logrotate.conf").read
    assert_includes conf, "weekly"
    assert_includes conf, "rotate 12"
    assert_includes conf, "compress"
    assert_includes conf, "create 0640"
  end
end
