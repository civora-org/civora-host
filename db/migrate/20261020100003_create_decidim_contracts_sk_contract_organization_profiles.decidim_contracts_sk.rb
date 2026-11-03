# frozen_string_literal: true

# Creates the per-organization profile that holds the town's contract header
# (civora-org/civora-platform#211, step P1; founder decision: an allowlisted
# JSON, not one column per field).
#
# Additive and reversible (`change` creates one table, `down` drops it). No
# backfill: an organization without a row simply has no header yet.
#
# - one row per organization: the unique index on the organization reference
#   is the backstop for the model's uniqueness validation;
# - `header` is a JSON column. Which keys it may hold, and their formats, is
#   enforced by the model (an allowlist), so adding a key later needs no
#   migration. The values are the town's own public identifiers (name, seat,
#   IČO, bank account, statutory representative), never personal data of
#   citizens.
class CreateDecidimContractsSkContractOrganizationProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_contract_organization_profiles do |t|
      t.references :decidim_organization, null: false, index: false,
                                          foreign_key: { to_table: :decidim_organizations }
      t.json :header, null: false, default: {}
      t.timestamps
    end

    add_index :decidim_contracts_sk_contract_organization_profiles,
              :decidim_organization_id,
              unique: true,
              name: "idx_contracts_sk_org_profiles_unique_organization"
  end
end
