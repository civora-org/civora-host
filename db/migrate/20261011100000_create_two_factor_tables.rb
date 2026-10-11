# frozen_string_literal: true

# Admin second factor (civora-org/civora-platform#164, ADR-010). Three new
# tables of our own; nothing in Decidim's tables is altered.
class CreateTwoFactorTables < ActiveRecord::Migration[7.2]
  def change
    # One TOTP credential per user. The seed is stored encrypted
    # (Decidim::AttributeEncryptor), never in clear text. A row without
    # confirmed_at is a pending enrolment and does not count as a second factor.
    create_table :civora_two_factor_credentials do |t|
      t.references :decidim_user, null: false, index: { unique: true }, foreign_key: { to_table: :decidim_users, on_delete: :cascade }
      t.text :otp_secret_ciphertext, null: false
      t.bigint :consumed_timestep # last accepted TOTP time step; blocks replay of a used code
      t.datetime :confirmed_at
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_at
      t.timestamps
    end

    # Single-use recovery codes, stored only as keyed digests.
    create_table :civora_two_factor_recovery_codes do |t|
      t.references :credential, null: false, foreign_key: { to_table: :civora_two_factor_credentials, on_delete: :cascade }
      t.string :code_digest, null: false
      t.datetime :used_at
      t.timestamps
      t.index [:credential_id, :code_digest], unique: true, name: "idx_civora_2fa_recovery_digest"
    end

    # Append-only audit trail. Holds no secrets and no personal data beyond the
    # user id; the id is not a foreign key so the trail outlives the user row.
    create_table :civora_two_factor_events do |t|
      t.bigint :decidim_user_id, null: false, index: true
      t.string :kind, null: false
      t.string :actor, null: false
      t.string :reason
      t.datetime :created_at, null: false
    end
  end
end
