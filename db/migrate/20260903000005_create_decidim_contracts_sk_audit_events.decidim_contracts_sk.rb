# frozen_string_literal: true

# Creates the engine's audit events table (M02-02-C,
# civora-org/civora-platform#57).
#
# Append-only audit trail: once written, records are never updated or deleted
# through the model (AuditEvent#readonly?). The polymorphic target carries no
# FK on purpose — dangling targets after target deletion are the Decidim
# ActionLog precedent, and the trail must survive what it observed.
#
# Tenancy is explicit here, unlike the contract-scoped parties/documents:
# because the target is polymorphic and can disappear, tenant scoping cannot
# be derived through it.
#
# Explicit index names follow the engine's "idx_contracts_sk_*" convention:
# the Rails-generated names for the organization and target indexes exceed
# PostgreSQL's 63-byte identifier limit.
class CreateDecidimContractsSkAuditEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_audit_events do |t|
      t.references :decidim_organization, null: false,
                                          foreign_key: { to_table: :decidim_organizations },
                                          index: { name: "idx_contracts_sk_audit_events_on_organization_id" }
      t.references :decidim_user, null: false,
                                  foreign_key: { to_table: :decidim_users },
                                  index: { name: "idx_contracts_sk_audit_events_on_user_id" }
      # t.references derives target_type (string) and target_id (bigint); no
      # FK is possible — or wanted — for a polymorphic target.
      t.references :target, polymorphic: true, null: false,
                            index: { name: "idx_contracts_sk_audit_events_on_target_type_and_target_id" }
      t.string :action, null: false
      t.timestamps
    end

    add_index :decidim_contracts_sk_audit_events, :created_at,
              name: "idx_contracts_sk_audit_events_on_created_at"
  end
end
