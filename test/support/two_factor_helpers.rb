# frozen_string_literal: true

require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"

# Synthetic users and sign-in helpers for the second-factor tests. Fictional data only.
module TwoFactorHelpers
  PASSWORD = "Tf-#{SecureRandom.hex(8)}-Xy9!".freeze # random per run, never a literal credential

  def build_organization
    FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")
  end

  def create_admin(organization)
    FactoryBot.create(:user, :confirmed, :admin, organization:, password: PASSWORD, password_confirmation: PASSWORD)
  end

  def create_participant(organization)
    FactoryBot.create(:user, :confirmed, organization:, password: PASSWORD, password_confirmation: PASSWORD)
  end

  def enrol!(user)
    credential = TwoFactor::Credential.build_pending(user)
    credential.confirmed_at = Time.current
    credential.save!
    credential
  end

  # The code the user's authenticator app would show right now.
  def current_code(credential, at: Time.current)
    credential.totp.at(at)
  end

  def sign_in_with_password(user)
    post "/sk/users/sign_in", params: { user: { email: user.email, password: PASSWORD } }
  end

  # Decidim 0.32 adds ?locale= to host-owned (un-scoped) routes and prefixes
  # its own with the locale, so compare the redirect target by path only.
  def assert_redirected_path(expected, message = nil)
    assert_response :redirect, message
    path = URI(response.location).path
    expected.is_a?(Regexp) ? assert_match(expected, path, message) : assert_equal(expected, path, message)
  end

  # CI compiles no webpack bundle, so asset lookups would raise on the empty
  # manifest; the pages under test do not depend on asset contents.
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
