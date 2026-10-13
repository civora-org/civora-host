# frozen_string_literal: true

module TwoFactor
  # Rewrites every TOTP seed with the current key derivation (SHA256 since
  # Decidim 0.32). Seeds written under 0.31 are SHA1-derived; Decidim's
  # AttributeEncryptor still reads them through a legacy fallback, but only
  # for as long as that fallback exists. `decidim:upgrade:encryption` knows
  # nothing about host tables, so this task covers ours (hooked in
  # lib/tasks/civora_upgrade.rake). Idempotent; prints no secret material.
  module Reencryption
    module_function

    # Returns the number of credentials rewritten.
    def call
      count = 0
      TwoFactor::Credential.where.not(otp_secret_ciphertext: [nil, ""]).find_each do |credential|
        credential.otp_secret = credential.otp_secret
        credential.save!
        count += 1
      end
      count
    end
  end
end
