# frozen_string_literal: true

require "test_helper"
require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"

# civora-org/civora-platform#133: the footer links to the accessibility
# statement once the page exists (host override of the footer main links),
# and shows no dead link before that.
class AccessibilityFooterLinkTest < ActionDispatch::IntegrationTest
  setup do
    @organization = FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")
    host! @organization.host
    stub_webpack_manifest
  end

  teardown { unstub_webpack_manifest }

  test "no footer link before the page exists" do
    get "/"

    assert_response :ok
    assert_select "footer a[href^=?]", "/pages/accessibility", count: 0
  end

  test "the footer links to the published statement, which renders for visitors" do
    AccessibilityStatement.call(@organization, contact_email: "access@example.org")

    get "/"
    assert_select "#panel-resources a[href^=?]", "/pages/accessibility", text: "Vyhlásenie o prístupnosti"

    get "/pages/accessibility"
    assert_response :ok
    assert_select "h2", text: "Stav súladu"
    assert_select "a[href=?]", "mailto:access@example.org"
  end

  test "the link follows the visitor's locale" do
    AccessibilityStatement.call(@organization)

    post "/locale", params: { locale: "en" }
    get "/"

    assert_select "#panel-resources a[href^=?]", "/pages/accessibility", text: "Accessibility statement"
  end

  private

  def stub_webpack_manifest
    @stubbed_manifest = Shakapacker.manifest
    @stubbed_names = [:lookup, :lookup!, :lookup_pack_with_chunks, :lookup_pack_with_chunks!]
    @stubbed_names.each do |name|
      chunks = name.to_s.include?("chunks")
      @stubbed_manifest.define_singleton_method(name) { |*_args, **_opts| chunks ? ["/packs-test/stub.js"] : "/packs-test/stub" }
    end
  end

  def unstub_webpack_manifest
    @stubbed_names&.each { |name| @stubbed_manifest.singleton_class.send(:remove_method, name) }
  end
end
