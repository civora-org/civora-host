# frozen_string_literal: true

require "test_helper"
require "support/two_factor_helpers"

# Rows encrypted under Decidim 0.31 use a SHA1-derived key. After the 0.32
# upgrade (SHA256) the app must still read them, the restore drill must
# accept them, and `civora:upgrade:encryption` must rewrite them.
#
# The ciphertexts below are real: produced by Rails 7.2.3.2 (load_defaults 7.2)
# with decidim-core 0.31.7's AttributeEncryptor logic, i.e.
#   key = ActiveSupport::KeyGenerator.new("attribute", hash_digest_class: SHA1)
#           .generate_key(secret_key_base, MessageEncryptor.key_len)
#   ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign(value)
# with a fixed, fictional secret_key_base. Plaintexts: a TOTP seed and a JSON string.
class LegacySha1EncryptionTest < ActiveSupport::TestCase
  include TwoFactorHelpers

  LEGACY_SECRET = ("0" * 128).freeze
  LEGACY_SEED = "JBSWY3DPEHPK3PXP"
  LEGACY_SEED_CIPHERTEXT = "FT8zoCpFdZSpGXMQr1WZMCSB--xsgbkqAK9p87E5Ao--FpWxgaWTEvSE+RsDln89TQ=="
  LEGACY_VALUE_CIPHERTEXT = "UY8twU+RjA441+Iu7rzy6tDWhh9ORkIbBqyAArqH--fSRLMKQNm/lkaWiC--5xblkEbm7LRlbUwuzTwhHQ=="

  setup do
    @organization = build_organization
    @user = create_admin(@organization)
    @original_cryptor = Decidim::AttributeEncryptor.instance_variable_get(:@cryptor)
    @original_secret = Rails.application.config.secret_key_base
    # The app as it runs after the upgrade: the SECRET_KEY_BASE of the old
    # installation is unchanged. It is set globally on purpose: the encryptor's
    # SHA1 fallback builds its own instance and reads Rails.application.secret_key_base.
    Rails.application.config.secret_key_base = LEGACY_SECRET
    Decidim::AttributeEncryptor.instance_variable_set(:@cryptor, Decidim::AttributeEncryptor.new(secret: "attribute"))
  end

  teardown do
    Rails.application.config.secret_key_base = @original_secret
    Decidim::AttributeEncryptor.instance_variable_set(:@cryptor, @original_cryptor)
  end

  test "a 0.31 TOTP seed still decrypts and the restore drill accepts it" do
    credential = legacy_credential

    assert_equal LEGACY_SEED, credential.otp_secret
    result = RestoreDrill::EncryptionCheck.call

    assert_equal :ok, result.status
    assert_equal({ "two_factor_credentials" => 1 }, result.verified)
  end

  test "a 0.31 authorization value passes the restore drill" do
    FactoryBot.create(:authorization, :granted, user: @user, name: "dummy_authorization_handler", metadata: { "document_number" => "x" })
    Decidim::Authorization.update_all(metadata: { "document_number" => LEGACY_VALUE_CIPHERTEXT }) # rubocop:disable Rails/SkipsModelValidations

    result = RestoreDrill::EncryptionCheck.call

    assert_equal :ok, result.status
    assert_equal({ "authorizations" => 1 }, result.verified)
  end

  test "the reencryption rewrites the seed with the SHA256 key and keeps the code valid" do
    credential = legacy_credential
    code_before = credential.totp.at(Time.zone.at(1_700_000_000))

    assert_equal 1, TwoFactor::Reencryption.call

    credential.reload
    assert_not_equal LEGACY_SEED_CIPHERTEXT, credential.otp_secret_ciphertext
    strict = Decidim::AttributeEncryptor.new(secret: "attribute", is_retry: true)

    assert_equal LEGACY_SEED, strict.decrypt(credential.otp_secret_ciphertext), "must decrypt without the SHA1 fallback"
    assert_equal code_before, credential.totp.at(Time.zone.at(1_700_000_000))
  end

  test "the rake task hooks into decidim:upgrade:encryption" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("civora:upgrade:encryption")

    assert_includes Rake::Task["decidim:upgrade:encryption"].prerequisites, "civora:upgrade:encryption"
  end

  private

  def legacy_credential
    TwoFactor::Credential.create!(user: @user, otp_secret: "placeholder").tap do |credential|
      credential.update_columns(otp_secret_ciphertext: LEGACY_SEED_CIPHERTEXT, confirmed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
