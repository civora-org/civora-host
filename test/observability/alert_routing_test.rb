# frozen_string_literal: true

require "test_helper"

# Offline pin of the Alertmanager routing (observability/alertmanager/
# alertmanager.yml) and its env rendering (entrypoint.sh) against
# docs/ops/observability.md: urgent alerts reach Telegram and e-mail, the rest
# e-mail only. Real delivery needs the Docker stack — see the doc's
# synthetic test 6.
class AlertRoutingTest < ActiveSupport::TestCase
  CONFIG_PATH = Rails.root.join("observability/alertmanager/alertmanager.yml").freeze
  ENTRYPOINT_PATH = Rails.root.join("observability/alertmanager/entrypoint.sh").freeze
  OVERLAY_PATH = Rails.root.join("compose.observability.yml").freeze

  test "critical and high go to telegram and continue to e-mail" do
    urgent, all = config.dig("route", "routes")
    assert_equal ['severity =~ "critical|high"'], urgent["matchers"]
    assert_equal "telegram", urgent["receiver"]
    assert urgent["continue"], "urgent alerts must also be e-mailed"
    assert_equal ['severity =~ "critical|high|warning"'], all["matchers"]
    assert_equal "email", all["receiver"]
  end

  test "unmatched alerts fall back to e-mail" do
    assert_equal "email", config.dig("route", "receiver")
  end

  test "every placeholder in the template is rendered by the entrypoint" do
    placeholders = File.readlines(CONFIG_PATH).grep_v(/^\s*#/).join.scan(/__[A-Z_]+__/).uniq
    entrypoint = File.read(ENTRYPOINT_PATH)
    assert_not_empty placeholders
    placeholders.each { |placeholder| assert_includes entrypoint, "s|#{placeholder}|", placeholder }
  end

  test "the overlay passes every rendered variable to alertmanager" do
    env = YAML.safe_load_file(OVERLAY_PATH, aliases: true).dig("services", "alertmanager", "environment")
    variables = File.read(ENTRYPOINT_PATH).scan(/\$\{(ALERT_[A-Z_]+):-/).flatten.uniq
    assert_equal variables.sort, env.keys.sort
  end

  test "telegram uses the custom HTML message template that the overlay mounts" do
    telegram = config["receivers"].find { |r| r["name"] == "telegram" }["telegram_configs"].first
    assert_equal "HTML", telegram["parse_mode"]
    assert_equal '{{ template "civora.telegram.message" . }}', telegram["message"]
    assert_includes Rails.root.join("observability/alertmanager/templates/telegram.tmpl").read,
                    '{{ define "civora.telegram.message" -}}'
    volumes = YAML.safe_load_file(OVERLAY_PATH, aliases: true).dig("services", "alertmanager", "volumes")
    assert_includes volumes, "./observability/alertmanager/templates:/etc/alertmanager/templates:ro"
  end

  private

  def config
    @config ||= YAML.safe_load_file(CONFIG_PATH)
  end
end
