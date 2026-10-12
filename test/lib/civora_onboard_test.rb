# frozen_string_literal: true

require "test_helper"
require "rake"
require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"

# Municipality onboarding (docs/ops/onboard-municipality.md): IČO validation,
# config loading, the idempotent organization/admin provisioning and the
# rate-limit-resuming first sync. No network: the sync runner is a stub.
class CivoraOnboardTest < ActiveSupport::TestCase
  VALID_ICO = "00313271"
  PASSWORD = "Sample-Pass-9f3k2lq8x7zv"

  def config_data(overrides = {})
    {
      "host" => "vranov.localhost", "name" => { "sk" => "Mesto Testov", "en" => "Town of Testov" },
      "short_name" => "Testov", "reference_prefix" => "tst", "ico" => VALID_ICO,
      "admin_email" => "Onboard-Admin@example.org"
    }.merge(overrides)
  end

  def config(overrides = {})
    CivoraOnboard::Config.new(config_data(overrides))
  end

  # --- IČO -------------------------------------------------------------

  test "ico checksum accepts valid numbers and rejects typos" do
    assert CivoraOnboard::Ico.checksum_valid?(VALID_ICO)
    assert CivoraOnboard::Ico.checksum_valid?("00151653")
    assert_not CivoraOnboard::Ico.checksum_valid?("00313272")
    assert_not CivoraOnboard::Ico.checksum_valid?("313271")
    assert_not CivoraOnboard::Ico.checksum_valid?("0031327a")
  end

  test "ico validate! normalizes spaces and explains failures" do
    assert_equal VALID_ICO, CivoraOnboard::Ico.validate!("00 313 271")
    assert_raises(ArgumentError) { CivoraOnboard::Ico.validate!(nil) }
    assert_match(/8 digits/, assert_raises(ArgumentError) { CivoraOnboard::Ico.validate!("1234") }.message)
    assert_match(/checksum/, assert_raises(ArgumentError) { CivoraOnboard::Ico.validate!("00313272") }.message)
  end

  test "env line is the exact variable the initializer reads" do
    assert_equal "CRZ_ICO_ORG_7=00313271", CivoraOnboard::Ico.env_line(7, VALID_ICO)
  end

  # --- config ----------------------------------------------------------

  test "config applies Slovak defaults and normalizes input" do
    cfg = config
    assert_equal "sk", cfg.default_locale
    assert_equal %w(sk en), cfg.available_locales
    assert_equal "Bratislava", cfg.time_zone
    assert_equal "TST", cfg.reference_prefix
    assert_equal "onboard-admin@example.org", cfg.admin_email
    assert_equal({ "sk" => "Mesto Testov", "en" => "Town of Testov" }, cfg.localized_name)
  end

  test "config rejects a bad host, locale, time zone and IČO together" do
    error = assert_raises(ArgumentError) do
      config("host" => "https://x.example/path", "default_locale" => "de", "time_zone" => "Nowhere", "ico" => "00313272")
    end
    assert_match(/checksum/, error.message)

    error = assert_raises(ArgumentError) { config("host" => "https://x.example/path", "time_zone" => "Nowhere") }
    assert_match(/host/, error.message)
    assert_match(/time_zone/, error.message)
  end

  test "config loads from YAML and the shipped example is valid" do
    cfg = CivoraOnboard::Config.load(Rails.root.join("config/onboarding/example.yml"))
    assert_equal "vranov.localhost", cfg.host
    assert_raises(ArgumentError) { CivoraOnboard::Config.load(Rails.root.join("config/onboarding/missing.yml")) }
  end

  # --- provisioning ----------------------------------------------------

  test "creates the organization through Decidim's system command and activates the admin" do
    result = CivoraOnboard::OrganizationProvisioner.call(config, admin_password: PASSWORD)
    org = result.organization.reload

    assert result.created
    assert_equal "vranov.localhost", org.host
    assert_equal "sk", org.default_locale
    assert_equal %w(sk en), org.available_locales
    assert_equal "Bratislava", org.time_zone
    assert_equal "TST", org.reference_prefix
    assert_equal "Town of Testov", org.name["en"]
    assert_equal "Mesto Testov", org.name["sk"]
    assert org.static_pages.any?, "Decidim's default pages are created by the system command"
    assert Decidim::ContentBlock.where(organization: org).any?, "default content blocks are created by the system command"

    admin = Decidim::User.find_by!(organization: org, email: "onboard-admin@example.org")
    assert admin.admin?
    assert admin.confirmed?
    assert admin.admin_terms_accepted_at.present?
    assert admin.valid_password?(PASSWORD)
    assert_equal :password_set, result.admin_status
  end

  test "is idempotent and does not overwrite an existing admin password" do
    first = CivoraOnboard::OrganizationProvisioner.call(config, admin_password: PASSWORD)
    counts = [Decidim::Organization.count, Decidim::User.count, Decidim::StaticPage.count]

    second = CivoraOnboard::OrganizationProvisioner.call(config, admin_password: "Another-Pass-1q2w3e4r5t6y")

    assert_not second.created
    assert_equal first.organization.id, second.organization.id
    assert_empty second.changes
    assert_equal :ready, second.admin_status
    assert_equal counts, [Decidim::Organization.count, Decidim::User.count, Decidim::StaticPage.count]
    assert Decidim::User.find_by!(email: "onboard-admin@example.org", organization: first.organization).valid_password?(PASSWORD)
  end

  test "a re-run converges changed settings without recreating" do
    first = CivoraOnboard::OrganizationProvisioner.call(config)
    assert_equal :invited, first.admin_status

    second = CivoraOnboard::OrganizationProvisioner.call(config("time_zone" => "UTC", "reference_prefix" => "NEW"))
    assert_not second.created
    assert_includes second.changes, :time_zone
    assert_includes second.changes, :reference_prefix
    assert_equal "UTC", first.organization.reload.time_zone
  end

  test "dry run writes nothing" do
    assert_no_difference -> { Decidim::Organization.count + Decidim::User.count } do
      result = CivoraOnboard::OrganizationProvisioner.call(config, admin_password: PASSWORD, dry_run: true)
      assert_nil result.organization
      assert_equal :would_invite, result.admin_status
    end
  end

  # --- first sync with resume --------------------------------------------

  STOP = "  sync stopped early: CRZ import gave up on https://datahub.ekosystem.slovensko.digital/api/data/crz/contracts/sync?" \
         "since=%{since}&last_id=99 after 6 attempts\n"

  def stop_output(since_escaped)
    format(STOP, since: since_escaped)
  end

  def sync_pass(success, output = "", since: nil)
    CivoraOnboard::SyncResume::Pass.new(since:, success:, output:)
  end

  test "resume_since parses and unescapes the since of the stop message" do
    assert_equal "2026-03-04T05:06:07Z", CivoraOnboard::SyncResume.resume_since(stop_output("2026-03-04T05%3A06%3A07Z"))
    assert_nil CivoraOnboard::SyncResume.resume_since("sync stopped early: boom")
    assert_nil CivoraOnboard::SyncResume.resume_since(stop_output("garbage"))
    assert_nil CivoraOnboard::SyncResume.resume_since("created=3")
  end

  test "waits for the rate window and continues from the parsed since until done" do
    sinces = []
    sleeps = []
    outputs = [
      sync_pass(false, stop_output("2026-01-10T00%3A00%3A00Z")),
      sync_pass(false, stop_output("2026-01-20T00%3A00%3A00Z")),
      sync_pass(true, "created=5")
    ]
    runner = lambda do |_org, since|
      sinces << since
      outputs.shift
    end

    outcome = CivoraOnboard::SyncResume.new(organization_id: 1, since: "2026-01-01T00:00:00Z", runner:,
                                            sleeper: ->(s) { sleeps << s }, log: ->(_) {}).call

    assert outcome.complete?
    assert_equal 3, outcome.passes
    assert_equal %w(2026-01-01T00:00:00Z 2026-01-10T00:00:00Z 2026-01-20T00:00:00Z), sinces
    assert_equal [65, 65], sleeps
  end

  test "stops without retrying on a non-rate-limit failure" do
    runner = ->(_org, _since) { sync_pass(false, "No import actor for organization #1") }
    sleeps = []
    outcome = CivoraOnboard::SyncResume.new(organization_id: 1, since: "2026-01-01T00:00:00Z", runner:,
                                            sleeper: ->(s) { sleeps << s }, log: ->(_) {}).call
    assert_equal :failed, outcome.status
    assert_equal 1, outcome.passes
    assert_empty sleeps
  end

  test "gives up when the same since keeps failing (no progress)" do
    runner = ->(_org, _since) { sync_pass(false, stop_output("2026-01-01T00%3A00%3A00Z")) }
    outcome = CivoraOnboard::SyncResume.new(organization_id: 1, since: "2026-01-01T00:00:00Z", runner:,
                                            sleeper: ->(_) {}, max_stalls: 3, log: ->(_) {}).call
    assert_equal :stalled, outcome.status
    assert_equal 3, outcome.passes
  end

  test "is bounded by max passes" do
    n = 0
    runner = lambda do |_org, _since|
      n += 1
      sync_pass(false, stop_output(format("2026-01-%02dT00%%3A00%%3A00Z", n + 1)))
    end
    outcome = CivoraOnboard::SyncResume.new(organization_id: 1, since: "2026-01-01T00:00:00Z", runner:,
                                            sleeper: ->(_) {}, max_passes: 4, log: ->(_) {}).call
    assert_equal :max_passes, outcome.status
    assert_equal 4, outcome.passes
  end

  test "rejects an invalid since before running anything" do
    runner = ->(*) { flunk "must not run" }
    assert_raises(ArgumentError) do
      CivoraOnboard::SyncResume.new(organization_id: 1, since: "yesterday", runner:, log: ->(_) {}).call
    end
  end

  # --- verification ----------------------------------------------------

  test "verification reports the IČO, admin and unique-IČO checks" do
    result = CivoraOnboard::OrganizationProvisioner.call(config, admin_password: PASSWORD)
    org = result.organization
    other = FactoryBot.create(:organization)
    original = Decidim::ContractsSk.crz_organization_ico_resolver
    Decidim::ContractsSk.crz_organization_ico_resolver = ->(o) { VALID_ICO if [org.id, other.id].include?(o.id) }

    checks = CivoraOnboard::Verification.call(org).index_by(&:label)

    assert checks.fetch("CRZ IČO configured").ok
    assert checks.fetch("An admin can sign in").ok
    assert checks.fetch("Slovak defaults").ok
    assert_not checks.fetch("IČO is unique to this organization").ok
    assert checks.fetch("Only this city's contracts are mirrored").ok
  ensure
    Decidim::ContractsSk.crz_organization_ico_resolver = original
  end

  test "verification fails closed when no IČO is configured" do
    org = CivoraOnboard::OrganizationProvisioner.call(config).organization
    original = Decidim::ContractsSk.crz_organization_ico_resolver
    Decidim::ContractsSk.crz_organization_ico_resolver = ->(_o) {}

    checks = CivoraOnboard::Verification.call(org)

    assert_not checks.find { |c| c.label == "CRZ IČO configured" }.ok
    assert_not checks.find { |c| c.label == "An admin can sign in" }.ok
  ensure
    Decidim::ContractsSk.crz_organization_ico_resolver = original
  end
end
