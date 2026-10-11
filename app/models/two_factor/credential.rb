# frozen_string_literal: true

module TwoFactor
  # A user's TOTP credential. The seed is encrypted at rest with
  # Decidim::AttributeEncryptor (AES-256-GCM, key derived from secret_key_base).
  class Credential < ApplicationRecord
    # The counters and the replay guard use single-statement updates on purpose:
    # they are atomic, which a load-modify-save cycle is not under concurrent
    # requests. Hence the disable below.
    # rubocop:disable Rails/SkipsModelValidations
    ISSUER = "Civora"
    DIGITS = 6
    MAX_FAILED_ATTEMPTS = 5
    LOCK_DURATION = 15.minutes
    DRIFT = 30 # seconds accepted either side of "now"

    belongs_to :user, class_name: "Decidim::User", foreign_key: :decidim_user_id, inverse_of: false
    has_many :recovery_codes, class_name: "TwoFactor::RecoveryCode", dependent: :delete_all

    scope :confirmed, -> { where.not(confirmed_at: nil) }

    # A fresh pending credential with a new random seed.
    def self.build_pending(user)
      new(user:, otp_secret: ROTP::Base32.random)
    end

    def otp_secret
      Decidim::AttributeEncryptor.decrypt(otp_secret_ciphertext)
    end

    def otp_secret=(value)
      self.otp_secret_ciphertext = Decidim::AttributeEncryptor.encrypt(value)
    end

    def confirmed?
      confirmed_at.present?
    end

    def totp
      ROTP::TOTP.new(otp_secret, issuer: ISSUER, digits: DIGITS)
    end

    def provisioning_uri
      totp.provisioning_uri(user.email)
    end

    def locked?
      locked_at.present? && locked_at > LOCK_DURATION.ago
    end

    # Verifies a six-digit TOTP code. A code is accepted once: its time step is
    # stored atomically, so a replay (or a second request racing the first) fails.
    # Returns :ok, :invalid or :locked.
    def verify_totp(code)
      guard_attempt { totp_valid?(code) }
    end

    # Spends a recovery code. Returns :ok, :invalid or :locked.
    def verify_recovery_code(code)
      guard_attempt { RecoveryCode.consume!(self, code) }
    end

    def confirm!(code)
      return :already_confirmed if confirmed?

      result = verify_totp(code)
      update!(confirmed_at: Time.current) if result == :ok
      result
    end

    def unused_recovery_codes_count
      recovery_codes.unused.count
    end

    private

    def totp_valid?(code)
      digits = code.to_s.gsub(/\s/, "")
      return false unless digits.match?(/\A\d{#{DIGITS}}\z/o)

      step = totp.verify(digits, drift_behind: DRIFT, drift_ahead: DRIFT, after: consumed_timestep)
      return false unless step

      self.class.where(id:).where("consumed_timestep IS NULL OR consumed_timestep < ?", step)
          .update_all(consumed_timestep: step) == 1
    end

    def guard_attempt
      reset_expired_lock!
      return :locked if locked?

      if yield
        self.class.where(id:).update_all(failed_attempts: 0, locked_at: nil)
        :ok
      else
        register_failure!
        locked? ? :locked : :invalid
      end
    end

    def register_failure!
      self.class.where(id:).update_all("failed_attempts = failed_attempts + 1")
      reload
      return unless failed_attempts >= MAX_FAILED_ATTEMPTS && locked_at.nil?

      update_columns(locked_at: Time.current)
      Event.record!(decidim_user_id, "locked", actor: "self")
    end

    def reset_expired_lock!
      return unless locked_at.present? && !locked?

      update_columns(failed_attempts: 0, locked_at: nil)
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
