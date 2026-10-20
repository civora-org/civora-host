# frozen_string_literal: true

module RestoreDrill
  # Proves that the running app can decrypt data encrypted by the backed-up
  # installation, i.e. that it booted with the backup's own SECRET_KEY_BASE
  # (civora-org/civora-platform#196). Row counts and an HTTP 200 pass with any
  # key; only a decrypt catches a key that would lock every admin out after a
  # real restore.
  #
  # Reads a sample of each kind of encrypted row through Decidim's own
  # AttributeEncryptor and reports counts only, never plaintext or ciphertext.
  #   * two_factor_credentials: the TOTP seed decrypts and yields a code.
  #   * authorizations: every encrypted metadata value decrypts. This reads the
  #     raw column: Decidim::RecordEncryptor swallows InvalidMessage in the
  #     model getter (legacy-plaintext fallback), so the getter would "succeed"
  #     with a wrong key.
  #   * contract_template_entries (civora-org/civora-platform#211): the
  #     personal_values of an entry decrypt with the backup's Active Record
  #     Encryption keys. Skipped when the installed engine predates the model.
  class EncryptionCheck
    SAMPLE = 50
    TEMPLATE_ENTRY_MODEL = "Decidim::ContractsSk::ContractTemplateEntry"

    Result = Struct.new(:status, :verified, :failed, keyword_init: true) do
      # :ok     at least one encrypted row decrypted and none failed
      # :failed at least one sampled row did not decrypt
      # :none   no encrypted rows exist, so nothing was verified (a warning)
      def exit_code
        { ok: 0, failed: 1, none: 3 }.fetch(status)
      end

      def summary
        counts = ->(h) { h.empty? ? "none" : h.map { |kind, n| "#{kind}=#{n}" }.join(" ") }
        case status
        when :ok then "encryption check OK: decrypted #{counts.call(verified)}"
        when :failed then "encryption check FAILED: could not decrypt #{counts.call(failed)} (verified: #{counts.call(verified)}). " \
                          "The app is not running with the backup's SECRET_KEY_BASE and Active Record Encryption keys."
        else "encryption check WARNING: no encrypted rows to verify (nothing was proven)"
        end
      end
    end

    def self.call(**)
      new(**).call
    end

    # entry_model: the contract template entry class; resolved lazily so a host
    # on an engine release without templates simply has nothing to check.
    def initialize(entry_model: TEMPLATE_ENTRY_MODEL.safe_constantize)
      @entry_model = entry_model
    end

    def call
      verified = Hash.new(0)
      failed = Hash.new(0)
      credentials(verified, failed)
      authorizations(verified, failed)
      template_entries(verified, failed)

      status = if failed.any? then :failed
               elsif verified.empty? then :none
               else
                 :ok
               end
      Result.new(status:, verified: verified.to_h, failed: failed.to_h)
    end

    private

    def credentials(verified, failed)
      TwoFactor::Credential.where.not(otp_secret_ciphertext: [nil, ""]).order(:id).limit(SAMPLE).each do |credential|
        usable = credential.otp_secret.present? && credential.totp.now.to_s.match?(/\A\d{#{TwoFactor::Credential::DIGITS}}\z/o)
        tally(usable, "two_factor_credentials", verified, failed)
      rescue StandardError
        tally(false, "two_factor_credentials", verified, failed)
      end
    end

    def authorizations(verified, failed)
      Decidim::Authorization.order(:id).limit(SAMPLE).each do |authorization|
        values = authorization[:metadata].is_a?(Hash) ? authorization[:metadata].values.grep(String) : []
        next if values.empty?

        decrypted = values.all? { |value| Decidim::AttributeEncryptor.decrypt(value).present? }
        tally(decrypted, "authorizations", verified, failed)
      rescue StandardError
        tally(false, "authorizations", verified, failed)
      end
    end

    # personal_values is read through the model, which raises on a key that does
    # not match (there is no plaintext fallback: support_unencrypted_data is
    # off). Rows with nothing stored prove nothing and are not counted.
    def template_entries(verified, failed)
      return unless @entry_model&.table_exists?

      @entry_model.order(:id).limit(SAMPLE).each do |entry|
        next if entry.personal_values_before_type_cast.blank?

        tally(entry.personal_values.is_a?(Hash), "contract_template_entries", verified, failed)
      rescue StandardError
        tally(false, "contract_template_entries", verified, failed)
      end
    end

    def tally(success, kind, verified, failed)
      (success ? verified : failed)[kind] += 1
    end
  end
end
