# frozen_string_literal: true

module TwoFactor
  # A single-use recovery code. Only a keyed SHA-256 digest is stored; the
  # plain code is shown once at generation. The codes are random (60 bits), so
  # a keyed fast digest is sufficient and allows a direct, constant-cost lookup.
  class RecoveryCode < ApplicationRecord
    ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789".chars.freeze
    COUNT = 10
    GROUPS = 3
    GROUP_LENGTH = 4

    belongs_to :credential, class_name: "TwoFactor::Credential"

    scope :unused, -> { where(used_at: nil) }

    # Returns the plain codes ("abcd-efgh-jkmn"); the caller shows them once.
    def self.generate_for!(credential)
      plain = Array.new(COUNT) { random_code }
      transaction do
        credential.recovery_codes.delete_all
        plain.each { |code| credential.recovery_codes.create!(code_digest: digest(code)) }
      end
      plain
    end

    def self.random_code
      Array.new(GROUPS) { Array.new(GROUP_LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join }.join("-")
    end

    def self.normalize(code)
      code.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end

    def self.digest(code)
      OpenSSL::HMAC.hexdigest("SHA256", digest_key, normalize(code))
    end

    def self.digest_key
      @digest_key ||= Rails.application.key_generator.generate_key("civora two factor recovery codes", 32)
    end

    # Atomically spends a code; true exactly once per code, even under races.
    def self.consume!(credential, code)
      return false if normalize(code).length != GROUPS * GROUP_LENGTH

      credential.recovery_codes.unused.where(code_digest: digest(code)).update_all(used_at: Time.current, updated_at: Time.current) == 1 # rubocop:disable Rails/SkipsModelValidations -- atomic single use
    end
  end
end
