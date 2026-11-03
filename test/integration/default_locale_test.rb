# frozen_string_literal: true

require "test_helper"
require "support/two_factor_helpers"

# Decidim 0.32.2 redirects "/" to the locale picked by
# Decidim::LocaleRouterDetector (params, session, user, then I18n.locale),
# before the organization's default_locale. The host therefore defaults the
# global locale to Slovak (config/application.rb).
class DefaultLocaleTest < ActionDispatch::IntegrationTest
  include TwoFactorHelpers

  setup do
    @organization = build_organization # default locale sk, available sk and en
    host! @organization.host
    stub_webpack_manifest
  end

  teardown { unstub_webpack_manifest }

  test "the global locale defaults are Slovak first" do
    assert_equal :sk, I18n.default_locale
    assert_equal "sk", Decidim.default_locale
    assert_equal %w(sk en), Decidim.available_locales.map(&:to_s)
  end

  test "an anonymous visitor of the root is sent to the Slovak home page" do
    get "/"

    assert_response :redirect
    assert_equal "/sk", URI(response.location).path.chomp("/")
  end
end
