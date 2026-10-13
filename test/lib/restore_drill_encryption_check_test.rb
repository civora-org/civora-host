# frozen_string_literal: true

require "test_helper"
require "support/two_factor_helpers"

# civora-org/civora-platform#196: the restore drill must prove the app can decrypt
# the backup's encrypted rows. Rows are written with the test key, then read back
# with the right key (decrypts) and with a random "wrong" key (must fail).
class RestoreDrillEncryptionCheckTest < ActiveSupport::TestCase
  include TwoFactorHelpers

  setup do
    @organization = build_organization
    @user = create_admin(@organization)
  end

  test "reports no encrypted rows as a warning, not a pass" do
    result = RestoreDrill::EncryptionCheck.call

    assert_equal :none, result.status
    assert_equal 3, result.exit_code
    assert_match(/WARNING: no encrypted rows to verify/, result.summary)
  end

  test "passes when a TOTP seed decrypts with the right key" do
    enrol!(@user)

    result = RestoreDrill::EncryptionCheck.call

    assert_equal :ok, result.status
    assert_equal 0, result.exit_code
    assert_equal({ "two_factor_credentials" => 1 }, result.verified)
  end

  test "fails when the TOTP seed was encrypted under a different key" do
    enrol!(@user)

    with_wrong_key do
      result = RestoreDrill::EncryptionCheck.call

      assert_equal :failed, result.status
      assert_equal 1, result.exit_code
      assert_equal({ "two_factor_credentials" => 1 }, result.failed)
      assert_match(/FAILED/, result.summary)
    end
  end

  test "passes when encrypted authorization metadata decrypts with the right key" do
    create_authorization

    result = RestoreDrill::EncryptionCheck.call

    assert_equal :ok, result.status
    assert_equal({ "authorizations" => 1 }, result.verified)
  end

  test "fails on authorization metadata under a different key even though the model getter hides it" do
    authorization = create_authorization

    with_wrong_key do
      result = RestoreDrill::EncryptionCheck.call

      assert_equal :failed, result.status
      assert_equal({ "authorizations" => 1 }, result.failed)
      # The Decidim getter swallows InvalidMessage, so it cannot be the probe.
      assert_nothing_raised { Decidim::Authorization.find(authorization.id).metadata }
    end
  end

  test "a failing row is not masked by a passing one" do
    enrol!(@user)
    create_authorization

    with_wrong_key do
      assert_equal :failed, RestoreDrill::EncryptionCheck.call.status
    end
  end

  test "the summary never contains secret or ciphertext material" do
    credential = enrol!(@user)

    with_wrong_key do
      summary = RestoreDrill::EncryptionCheck.call.summary

      assert_not_includes summary, credential.otp_secret_ciphertext
    end
    assert_not_includes RestoreDrill::EncryptionCheck.call.summary, credential.otp_secret
  end

  private

  def create_authorization
    FactoryBot.create(:authorization, :granted, user: @user, name: "dummy_authorization_handler",
                                                metadata: { "document_number" => "12345678X" })
  end

  # Swap Decidim's memoized cryptor for one keyed from a random secret_key_base.
  def with_wrong_key
    original = Decidim::AttributeEncryptor.instance_variable_get(:@cryptor)
    # 0.32's cryptor is an AttributeEncryptor. Keyed from another secret_key_base it cannot decrypt
    # what the test key wrote. Caveat: its SHA1 fallback (legacy_encryptor) is built without this
    # option and reads the REAL Rails.application.secret_key_base, but the seeds here are SHA256, so
    # the fallback cannot rescue them. Legacy (0.31, SHA1) rows are covered in legacy_sha1_encryption_test.rb.
    Decidim::AttributeEncryptor.instance_variable_set(:@cryptor, Decidim::AttributeEncryptor.new(secret: "attribute", secret_key_base: SecureRandom.hex(64)))
    yield
  ensure
    Decidim::AttributeEncryptor.instance_variable_set(:@cryptor, original)
  end
end
