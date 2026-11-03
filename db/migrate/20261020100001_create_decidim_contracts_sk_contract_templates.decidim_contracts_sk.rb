# frozen_string_literal: true

# Creates the versioned contract templates table (civora-org/civora-platform
# #211, step P1). A row is one version of one template lineage: the Word
# source file (attached through ActiveStorage, which the host already owns)
# plus the metadata the generator needs.
#
# Additive and reversible: a single `change` that only creates a table, so
# `down` drops it. No backfill, nothing existing is touched.
#
# Constraint policy mirrors the engine's precedents:
# - tenancy is explicit (`decidim_organization_id`, a real FK);
# - the unique (organization, lineage_key, version) index is the backstop for
#   the model's uniqueness validation (two concurrent "new version" requests)
#   and also serves the per-organization lookups;
# - `status` is a plain string validated by the model (draft/active/archived);
# - the creator is a plain bigint reference with NO foreign key and NO index
#   (the `decidim_author_id` precedent: a deleted user must not block or
#   cascade into the template history);
# - a version becomes immutable once an entry references it. That is a model
#   guard (it needs the entries table, created later), not a DB constraint.
class CreateDecidimContractsSkContractTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_contract_templates do |t|
      t.references :decidim_organization, null: false, index: false,
                                          foreign_key: { to_table: :decidim_organizations }
      t.string :lineage_key, null: false
      t.integer :version, null: false, default: 1
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.string :source_filename
      t.string :source_checksum
      t.string :reference_pattern
      t.references :decidim_created_by, null: true, index: false
      t.timestamps
    end

    add_index :decidim_contracts_sk_contract_templates,
              %i[decidim_organization_id lineage_key version],
              unique: true,
              name: "idx_contracts_sk_contract_templates_unique_version"
  end
end
