# frozen_string_literal: true

require "test_helper"
require "support/two_factor_helpers"

class TwoFactorCredentialTest < ActiveSupport::TestCase
  include TwoFactorHelpers

  setup do
    @organization = build_organization
    @user = create_admin(@organization)
    @credential = enrol!(@user)
  end

  test "the seed is encrypted at rest and decrypts back" do
    secret = @credential.otp_secret
    raw = TwoFactor::Credential.connection.select_value("SELECT otp_secret_ciphertext FROM civora_two_factor_credentials WHERE id = #{@credential.id}")

    assert_not_includes raw, secret
    assert_equal secret, TwoFactor::Credential.find(@credential.id).otp_secret
  end

  test "a valid code is accepted once and cannot be replayed" do
    code = current_code(@credential)

    assert_equal :ok, @credential.verify_totp(code)
    assert_equal :invalid, TwoFactor::Credential.find(@credential.id).verify_totp(code)
  end

  test "a malformed or wrong code is invalid" do
    ["", "abc", "1234567"].each do |code|
      assert_equal :invalid, @credential.verify_totp(code), code.inspect
    end
    wrong = format("%06d", (current_code(@credential).to_i + 1) % 1_000_000)

    assert_equal :invalid, @credential.verify_totp(wrong)
  end

  test "a code from the previous 30 second window is tolerated, two windows back is not" do
    assert_equal :ok, @credential.verify_totp(current_code(@credential, at: 25.seconds.ago))
    fresh = enrol!(create_admin(@organization))

    assert_equal :invalid, fresh.verify_totp(current_code(fresh, at: 95.seconds.ago))
  end

  test "five wrong codes lock the credential, even against a correct code, until the lock expires" do
    TwoFactor::Credential::MAX_FAILED_ATTEMPTS.times { assert_includes [:invalid, :locked], @credential.verify_totp("000000") }

    assert_predicate @credential, :locked?
    assert_equal :locked, @credential.verify_totp(current_code(@credential))
    assert_equal 1, TwoFactor::Event.where(decidim_user_id: @user.id, kind: "locked").count

    travel 16.minutes do
      assert_equal :ok, TwoFactor::Credential.find(@credential.id).verify_totp(current_code(@credential, at: Time.current))
    end
  end

  test "a successful verification clears earlier failures" do
    2.times { @credential.verify_totp("000000") }

    assert_equal :ok, @credential.verify_totp(current_code(@credential))
    assert_equal 0, @credential.reload.failed_attempts
  end

  test "recovery codes are stored hashed, ten per set, and each works once" do
    codes = TwoFactor::RecoveryCode.generate_for!(@credential)

    assert_equal 10, codes.size
    assert_equal 10, @credential.recovery_codes.count
    stored = @credential.recovery_codes.pluck(:code_digest)
    codes.each { |code| assert_not_includes stored, code }
    assert(stored.all? { |digest| digest.match?(/\A\h{64}\z/) })

    assert_equal :ok, @credential.verify_recovery_code(codes.first)
    assert_equal :invalid, @credential.verify_recovery_code(codes.first)
    assert_equal 9, @credential.unused_recovery_codes_count
  end

  test "recovery codes ignore case, dashes and spaces" do
    code = TwoFactor::RecoveryCode.generate_for!(@credential).first

    assert_equal :ok, @credential.verify_recovery_code(" #{code.upcase.delete("-")} ")
  end

  test "regenerating replaces the previous set" do
    old = TwoFactor::RecoveryCode.generate_for!(@credential).first
    TwoFactor::RecoveryCode.generate_for!(@credential)

    assert_equal :invalid, @credential.verify_recovery_code(old)
  end

  test "a recovery code of another credential is rejected" do
    other = enrol!(create_admin(@organization))
    code = TwoFactor::RecoveryCode.generate_for!(other).first

    assert_equal :invalid, @credential.verify_recovery_code(code)
  end

  test "events are append-only" do
    event = TwoFactor::Event.record!(@user.id, "enrolled", actor: "self")

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(kind: "reset") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy! }
  end
end
