# frozen_string_literal: true

require "test_helper"
require "rake"
require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"

# civora-org/civora-platform#133: the accessibility statement static page
# (sk + en), its idempotent creation and the rake task. Fictional data only.
class AccessibilityStatementTest < ActiveSupport::TestCase
  SECTIONS = {
    "sk" => ["Stav súladu", "Neprístupný obsah", "Príprava tohto vyhlásenia", "Spätná väzba a kontakt", "Postup presadzovania"],
    "en" => ["Compliance status", "Non-accessible content", "Preparation of this statement", "Feedback and contact",
             "Enforcement procedure"]
  }.freeze

  setup do
    @organization = FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")
  end

  def page_for(organization)
    Decidim::StaticPage.find_by!(organization: organization, slug: AccessibilityStatement::SLUG)
  end

  test "creates a public static page with the model-statement sections in sk and en" do
    result = AccessibilityStatement.call(@organization, contact_email: "access@example.org")
    page = result.page.reload

    assert result.created
    assert_equal "accessibility", page.slug
    assert page.allow_public_access
    assert_equal "Vyhlásenie o prístupnosti", page.title["sk"]
    assert_equal "Accessibility statement", page.title["en"]
    SECTIONS.each do |locale, headings|
      headings.each { |heading| assert_includes page.content[locale], "<h2>#{heading}</h2>" }
    end
  end

  test "is honest: partially compliant, manual screen-reader pass pending, dated, legal points flagged" do
    page = AccessibilityStatement.call(@organization).page.reload

    assert_includes page.content["sk"], "čiastočne v súlade"
    assert_includes page.content["sk"], "NVDA"
    assert_includes page.content["sk"], '<time datetime="2026-10-11">11. októbra 2026</time>'
    assert_includes page.content["sk"], AccessibilityStatement::VERIFY["sk"]
    assert_includes page.content["en"], "partially compliant"
    assert_includes page.content["en"], "not yet carried out manual testing"
    assert_includes page.content["en"], AccessibilityStatement::VERIFY["en"]
    assert_equal AccessibilityStatement::PREPARED_ON, Date.new(2026, 10, 11)
  end

  test "is idempotent: a re-run updates the one page and restores edited text" do
    AccessibilityStatement.call(@organization, contact_email: "access@example.org")
    page = page_for(@organization)
    page.update!(content: { "sk" => "ručne zmenené", "en" => "edited by hand" })

    second = AccessibilityStatement.call(@organization, contact_email: "access@example.org")

    assert_not second.created
    assert_equal 1, Decidim::StaticPage.where(organization: @organization, slug: "accessibility").count
    assert_includes page_for(@organization).content["sk"], "Stav súladu"
  end

  test "each organization gets its own page" do
    other = FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")

    AccessibilityStatement.call(@organization)
    AccessibilityStatement.call(other)

    assert_not_equal page_for(@organization).id, page_for(other).id
  end

  test "contact: explicit address wins, then the organization's sender address, then a visible placeholder" do
    @organization.update!(smtp_settings: { "from_email" => "register@example.org" })

    explicit = AccessibilityStatement.call(@organization, contact_email: " access@example.org ")
    assert_includes explicit.page.content["sk"], '<a href="mailto:access@example.org">access@example.org</a>'

    fallback = AccessibilityStatement.call(@organization)
    assert_equal "register@example.org", fallback.contact_email
    assert_includes fallback.page.content["en"], "mailto:register@example.org"

    @organization.update!(smtp_settings: {})
    placeholder = AccessibilityStatement.call(@organization)
    assert_nil placeholder.contact_email
    assert_includes placeholder.page.content["sk"], AccessibilityStatement::CONTACT_PLACEHOLDER["sk"]
    assert_not_includes placeholder.page.content["sk"], "mailto:"
  end

  test "escapes the contact address and the organization name in the page HTML" do
    @organization.update!(name: { "sk" => "<script>alert(1)</script>", "en" => "Town & Co" })

    page = AccessibilityStatement.call(@organization, contact_email: %(x"><img src=x onerror=1>@example.org)).page.reload

    assert_not_includes page.content["sk"], "<script>"
    assert_not_includes page.content["sk"], "<img"
    assert_includes page.content["en"], "Town &amp; Co"
  end

  test "the rake task publishes for every organization, honouring ACCESSIBILITY_CONTACT_EMAIL" do
    other = FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")
    task = rake_task

    with_env("ACCESSIBILITY_CONTACT_EMAIL" => "access@example.org") { capture_io { task.invoke } }

    [@organization, other].each do |organization|
      assert_includes page_for(organization).content["sk"], "mailto:access@example.org"
    end

    task.reenable
    out, = capture_io { with_env("ACCESSIBILITY_CONTACT_EMAIL" => "access@example.org") { task.invoke(@organization.id.to_s) } }
    assert_includes out, "Updated /pages/accessibility in organization ##{@organization.id}"
  end

  test "the rake task aborts for an unknown organization and creates nothing" do
    task = rake_task

    assert_raises(SystemExit) { capture_io { task.invoke("0") } }
    assert_not Decidim::StaticPage.exists?(organization: @organization, slug: "accessibility")
  end

  private

  def rake_task
    Rails.application.load_tasks unless Rake::Task.task_defined?("civora:accessibility_statement:publish")
    Rake::Task["civora:accessibility_statement:publish"].tap(&:reenable)
  end

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
