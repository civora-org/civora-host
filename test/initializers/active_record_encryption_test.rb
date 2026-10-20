# frozen_string_literal: true

require "test_helper"

# civora-org/civora-platform#211: the contracts engine encrypts personal values
# with Active Record Encryption, and this host owns the keys. A production boot
# without them must fail loudly; a rotation keeps the old key for decryption.
class ActiveRecordEncryptionTest < ActiveSupport::TestCase
  KEY = "a" * 40
  SALT = "b" * 40
  OLD_KEY = "c" * 40

  def configure(env, rails_env: "production")
    encryption = ActiveSupport::OrderedOptions.new
    ActiveRecordEncryptionSetup.configure(encryption, env:, rails_env: ActiveSupport::StringInquirer.new(rails_env))
    encryption
  end

  def production_env(extra = {})
    { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => KEY, "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => SALT }.merge(extra)
  end

  test "test environment has working keys, so encrypted attributes round-trip" do
    encryptor = ActiveRecord::Encryption.encryptor
    ciphertext = encryptor.encrypt("synthetic personal value")

    assert_not_equal "synthetic personal value", ciphertext
    assert_equal "synthetic personal value", encryptor.decrypt(ciphertext)
  end

  test "production reads both keys from the environment" do
    encryption = configure(production_env)

    assert_equal KEY, encryption.primary_key
    assert_equal SALT, encryption.key_derivation_salt
    assert_nil encryption.previous
  end

  test "production boot fails when the keys are missing" do
    error = assert_raises(RuntimeError) { configure({}) }

    assert_match(/Active Record Encryption keys are missing/, error.message)
    assert_no_match(/#{KEY}/, error.message)
  end

  test "production boot fails when only one key is set" do
    assert_raises(RuntimeError) { configure({ "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => KEY }) }
    assert_raises(RuntimeError) { configure({ "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => SALT }) }
  end

  test "blank values count as missing" do
    assert_raises(RuntimeError) { configure(production_env("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "  ")) }
  end

  test "production refuses short keys without echoing them" do
    error = assert_raises(RuntimeError) { configure(production_env("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "changeme")) }

    assert_match(/primary key shorter than 32/, error.message)
    assert_no_match(/changeme/, error.message)
  end

  test "the image build (assets precompile, dummy secret) boots without keys" do
    encryption = configure({ "SECRET_KEY_BASE_DUMMY" => "1" })

    assert_nil encryption.primary_key
  end

  test "development falls back to fixed non-secret keys" do
    encryption = configure({}, rails_env: "development")

    assert_equal ActiveRecordEncryptionSetup::DEV_PRIMARY_KEY, encryption.primary_key
    assert_equal ActiveRecordEncryptionSetup::DEV_SALT, encryption.key_derivation_salt
  end

  test "rotation: old primary keys are kept for decryption through previous" do
    encryption = configure(production_env("ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS" => " #{OLD_KEY}, ,#{OLD_KEY}x "))

    assert_equal KEY, encryption.primary_key
    assert_equal [{ key: OLD_KEY }, { key: "#{OLD_KEY}x" }], encryption.previous
  end

  test "data written under the old key stays readable after the key is rotated" do
    old = key_provider(OLD_KEY)
    ciphertext = ActiveRecord::Encryption::Encryptor.new.encrypt("synthetic", key_provider: old)

    rotated = ActiveRecord::Encryption::Scheme.new(key: KEY).key_provider
    assert_raises(ActiveRecord::Encryption::Errors::Decryption) do
      ActiveRecord::Encryption::Encryptor.new.decrypt(ciphertext, key_provider: rotated)
    end

    previous = ActiveRecord::Encryption::Scheme.new(**configure(production_env("ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS" => OLD_KEY)).previous.first)
    assert_equal "synthetic", ActiveRecord::Encryption::Encryptor.new.decrypt(ciphertext, key_provider: previous.key_provider)
  end

  private

  def key_provider(key)
    ActiveRecord::Encryption::DerivedSecretKeyProvider.new(key)
  end
end
