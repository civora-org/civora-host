# frozen_string_literal: true

# Active Record Encryption keys (civora-org/civora-platform#211).
#
# The contracts engine stores the personal-data values of a contract template
# entry (`personal_values`) with Active Record Encryption. Decidim does not
# configure it, so the host does. Secrets come from ENV only, like every other
# secret here (docs/ops/secrets.md); Rails credentials are retired.
#
#   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY          required in production, >= 32 chars
#   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT  required in production, >= 32 chars
#   ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS  optional, comma-separated old
#       primary keys kept for decryption during a rotation (same salt)
#
# Generate with `bin/rails db:encryption:init`. LOSING THESE KEYS MAKES EVERY
# STORED `personal_values` UNREADABLE: they are as critical as SECRET_KEY_BASE
# and travel with it in custody, backups and the restore drill
# (docs/ops/secrets.md, docs/ops/restore-runbook.md).
#
# Fail loudly: a production boot without both keys raises here, so a missing
# key is a deploy failure and never a runtime surprise at the first save. The
# asset-precompile step of the image build runs with SECRET_KEY_BASE_DUMMY and
# has no secrets, so it is the one exception. Development and test fall back to
# fixed, public keys (never valid in production, which refuses short or absent
# keys and does not read this fallback).
module ActiveRecordEncryptionSetup
  MIN_KEY_LENGTH = 32
  DEV_PRIMARY_KEY = "civora-host-dev-only-primary-key-not-a-secret"
  DEV_SALT = "civora-host-dev-only-key-derivation-salt-not-a-secret"

  module_function

  def configure(encryption, env: ENV, rails_env: Rails.env)
    primary, salt, previous = read_env(env)
    local = %w(development test).include?(rails_env.to_s)

    return configure_without_keys(encryption, env:, local:) if primary.empty? && salt.empty?

    check_together!(primary, salt)
    check_length!(primary, salt, previous) unless local
    encryption.primary_key = primary
    encryption.key_derivation_salt = salt
    encryption.previous = previous.map { |key| { key: } } if previous.any?
  end

  def read_env(env)
    [env["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].to_s.strip,
     env["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].to_s.strip,
     env["ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS"].to_s.split(",").map(&:strip).reject(&:empty?)]
  end

  def check_together!(primary, salt)
    return unless primary.empty? || salt.empty?

    raise "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY and ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT must be set together."
  end

  def configure_without_keys(encryption, env:, local:)
    return use_development_keys(encryption) if local
    return if env["SECRET_KEY_BASE_DUMMY"].present?

    raise "Active Record Encryption keys are missing: set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY and " \
          "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT (generate with `bin/rails db:encryption:init`; " \
          "see docs/ops/secrets.md). They protect the personal data of contract templates and must be the " \
          "same ones the database was written with."
  end

  # Names the offending value, never prints it.
  def check_length!(primary, salt, previous)
    named = { "primary key" => primary, "key derivation salt" => salt }
    previous.each_with_index { |key, i| named["previous primary key ##{i + 1}"] = key }
    short = named.select { |_, value| value.length < MIN_KEY_LENGTH }.keys
    raise "Active Record Encryption #{short.join(", ")} shorter than #{MIN_KEY_LENGTH} characters." if short.any?
  end

  # Rails applies config.active_record.encryption when ActiveRecord::Encryption
  # loads. A gem that loads it before the app's initializers (Decidim does)
  # has already been configured with nothing, so push the values into the live
  # config as well. Idempotent: `previous` replaces, never appends.
  def apply_to_loaded(encryption)
    live = ActiveRecord::Encryption.config
    live.primary_key = encryption.primary_key if encryption.primary_key
    live.key_derivation_salt = encryption.key_derivation_salt if encryption.key_derivation_salt
    return unless encryption.previous

    live.previous_schemes = []
    live.previous = encryption.previous
  end

  def use_development_keys(encryption)
    encryption.primary_key = DEV_PRIMARY_KEY
    encryption.key_derivation_salt = DEV_SALT
  end
end

ActiveRecordEncryptionSetup.configure(Rails.application.config.active_record.encryption)
ActiveRecordEncryptionSetup.apply_to_loaded(Rails.application.config.active_record.encryption)
