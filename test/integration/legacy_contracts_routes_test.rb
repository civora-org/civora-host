# frozen_string_literal: true

require "test_helper"
require "support/two_factor_helpers"

# The engine lives under /:locale/contracts since Decidim 0.32. The old
# un-prefixed URLs (bookmarks, open-data consumers, e-mails sent before the
# upgrade) must keep working: GET redirects permanently, POST is served in place.
class LegacyContractsRoutesTest < ActionDispatch::IntegrationTest
  include TwoFactorHelpers
  include Warden::Test::Helpers

  setup do
    @organization = build_organization # default locale sk, available sk and en
    host! @organization.host
    stub_webpack_manifest
  end

  teardown do
    Warden.test_reset!
    unstub_webpack_manifest
  end

  test "the catalogue redirects permanently to the organization's default locale" do
    get "/contracts"

    assert_response :moved_permanently
    assert_equal "/sk/contracts", URI(response.location).request_uri
  end

  test "the query string is kept and a locale parameter picks the locale and is dropped" do
    get "/contracts/suppliers?q=ihrisko&page=2&locale=en"

    assert_response :moved_permanently
    assert_equal "/en/contracts/suppliers?q=ihrisko&page=2", URI(response.location).request_uri
  end

  test "a file extension survives the redirect" do
    get "/contracts/export.csv?q=a"

    assert_response :moved_permanently
    assert_equal "/sk/contracts/export.csv?q=a", URI(response.location).request_uri
  end

  test "a forged locale falls back to the default and never leaves the site" do
    ["//evil.com", "https://evil.com", "xx", "sk/../../evil"].each do |forged|
      get "/contracts", params: { locale: forged }

      assert_response :moved_permanently, forged
      assert_equal "/sk/contracts", URI(response.location).request_uri, forged
      assert_equal @organization.host, URI(response.location).host, forged
    end
  end

  test "characters that are not valid in a location are escaped, not a 500" do
    ["/contracts/a%20b", "/contracts/%C5%A1tatistika", "/contracts/a%0Ab", "/contracts/a%22b%3Cc"].each do |path|
      get path

      assert_response :moved_permanently, path
      assert_match(%r{\A/sk/contracts/[^\s]+\z}, URI(response.location).request_uri, path)
    end
  end

  test "a malformed byte sequence is a client error, not a 500" do
    get "/contracts/%FF"

    assert_response :bad_request
  end

  test "an old admin link lands on the second-factor gate, not on the admin" do
    admin = create_admin(@organization)
    sign_in_with_password(admin)

    get "/contracts/admin/contracts"

    assert_response :moved_permanently
    follow_redirect!

    assert_redirected_path "/two_factor/enrolment"
  end

  test "the one-click unsubscribe POST of an e-mail sent before the upgrade is served, not redirected" do
    subscription = create_subscription

    assert_difference -> { Decidim::ContractsSk::Subscription.count }, -1 do
      post "/contracts/subscriptions/#{subscription.unsubscribe_token}/unsubscribe", params: { "List-Unsubscribe" => "One-Click" }
    end
    assert_response :ok
  end

  test "the prefixed unsubscribe POST works the same" do
    subscription = create_subscription

    assert_difference -> { Decidim::ContractsSk::Subscription.count }, -1 do
      post "/sk/contracts/subscriptions/#{subscription.unsubscribe_token}/unsubscribe"
    end
    assert_response :ok
  end

  test "a legacy POST with a bad token changes nothing" do
    create_subscription

    assert_no_difference -> { Decidim::ContractsSk::Subscription.count } do
      post "/contracts/subscriptions/#{"x" * 40}/unsubscribe"
    end
    assert_response :not_found
  end

  private

  def create_subscription
    result = Decidim::ContractsSk::CreateSubscription.call(
      organization: @organization, email: "reader-#{SecureRandom.hex(4)}@example.org", params: { "q" => "ihrisko" }, locale: "sk"
    )
    result.subscription
  end
end
