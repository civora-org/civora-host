# frozen_string_literal: true

require "test_helper"

# Structural, offline pin of the Prometheus alert rules
# (observability/prometheus/rules.yml) against the alert table and
# synthetic-failure runbook in docs/ops/observability.md. Whether alerts
# actually fire needs the Docker stack — that part is covered by the manual
# synthetic tests in the doc; this suite only guards against config/doc drift
# (wrong windows, thresholds, job names, or undocumented rules).
class AlertRulesTest < ActiveSupport::TestCase
  RULES_PATH = Rails.root.join("observability/prometheus/rules.yml").freeze
  PROMETHEUS_PATH = Rails.root.join("observability/prometheus/prometheus.yml").freeze
  DOC_PATH = Rails.root.join("docs/ops/observability.md").freeze

  EXPECTED_ALERTS = {
    "AppUptimeCritical" => { "severity" => "critical", "for" => "2m" },
    "AppUptimeHigh" => { "severity" => "high", "for" => "5m" },
    "DeepHealthCheckFailing" => { "severity" => "warning", "for" => "5m" },
    "HttpErrorRateCritical" => { "severity" => "critical", "for" => "2m" },
    "HttpErrorRateHigh" => { "severity" => "high", "for" => "5m" },
    "BackupStale" => { "severity" => "high", "for" => "10m" }
  }.freeze

  test "rules.yml parses and contains exactly the documented alerts" do
    assert_equal(EXPECTED_ALERTS.keys, rules.map { |rule| rule["alert"] })
  end

  test "each alert has the documented severity and hold time" do
    rules.each do |rule|
      expected = EXPECTED_ALERTS.fetch(rule["alert"])
      assert_equal expected["severity"], rule.dig("labels", "severity"), rule["alert"]
      assert_equal expected["for"], rule["for"], rule["alert"]
    end
  end

  test "uptime alerts use the blackbox-up probe with the documented windows" do
    assert_includes expr("AppUptimeCritical"),
                    'avg_over_time(probe_success{job="blackbox-up"}[5m]) < 0.95'
    assert_includes expr("AppUptimeHigh"),
                    'avg_over_time(probe_success{job="blackbox-up"}[1h]) < 0.99'
  end

  test "deep health alert watches the blackbox-healthz probe" do
    assert_includes expr("DeepHealthCheckFailing"),
                    'probe_success{job="blackbox-healthz"} == 0'
  end

  test "error rate alerts compare 5xx against total requests on the middleware metric" do
    assert_includes expr("HttpErrorRateCritical"),
                    'sum(rate(ruby_http_requests_total{status=~"5.."}[5m]))'
    assert_includes expr("HttpErrorRateCritical"), "> 0.05"
    assert_includes expr("HttpErrorRateHigh"),
                    'sum(rate(ruby_http_requests_total{status=~"5.."}[1h]))'
    assert_includes expr("HttpErrorRateHigh"), "> 0.01"
  end

  test "BackupStale is a 26h dead-man window with an absent() branch" do
    backup_expr = expr("BackupStale")
    assert_includes backup_expr, "time() - civora_backup_last_success_unixtime > 93600"
    assert_includes backup_expr, "absent(civora_backup_last_success_unixtime) == 1"
    # 26h stays above the largest nightly 03:15 Europe/Bratislava gap (24h,
    # 25h across the October DST fallback) so a successful push never trips
    # the alert, while one missed night (elapsed up to ~48h) does.
    assert_equal 26 * 60 * 60, 93_600
  end

  test "prometheus.yml wires the rule file and the probe jobs the rules rely on" do
    prometheus = YAML.safe_load_file(PROMETHEUS_PATH)
    assert_includes prometheus["rule_files"], "/etc/prometheus/rules.yml"
    # A 30s evaluation interval keeps the documented fire delays (for: 2m..10m)
    # meaningful relative to the windows above.
    assert_equal "30s", prometheus.dig("global", "evaluation_interval")

    jobs = prometheus["scrape_configs"].index_by { |job| job["job_name"] }
    assert_equal "http://app:3000/up", jobs.fetch("blackbox-up").dig("static_configs", 0, "targets", 0)
    assert_equal "http://app:3000/healthz", jobs.fetch("blackbox-healthz").dig("static_configs", 0, "targets", 0)
    # BackupStale's absent() branch only resolves if Prometheus scrapes the
    # pushgateway; honor_labels keeps the pushed job="civora-backup" label.
    pushgateway = jobs.fetch("pushgateway")
    assert_equal true, pushgateway["honor_labels"]
    assert_equal "pushgateway:9091", pushgateway.dig("static_configs", 0, "targets", 0)

    # Firing alerts must actually reach Alertmanager — verified live in the
    # #51 synthetic test (a missing alerting: section is silent at boot).
    alertmanager = prometheus.fetch("alerting").fetch("alertmanagers")
    assert_equal "alertmanager:9093",
                 alertmanager.first.dig("static_configs", 0, "targets", 0)
  end

  test "observability.md documents every rule (runbook must stay in sync with rules.yml)" do
    doc = DOC_PATH.read
    EXPECTED_ALERTS.each_key { |alert| assert_includes doc, alert }
    assert_includes doc, "03:15", "the doc should state the backup cron time the BackupStale window assumes"
  end

  private

  def rules
    @rules ||= YAML.safe_load_file(RULES_PATH)["groups"].flat_map { |group| group["rules"] }
  end

  def expr(alert)
    rules.find { |rule| rule["alert"] == alert }["expr"]
  end
end
