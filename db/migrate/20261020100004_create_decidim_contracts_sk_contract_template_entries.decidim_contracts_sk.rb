# frozen_string_literal: true

# Creates the table of filled-in template entries (civora-org/civora-platform
# #211, step P1): what an editor typed into a template's form for one
# contract.
#
# Additive and reversible (`change` creates one table, `down` drops it). No
# backfill.
#
# - one entry per contract (unique contract index, which also serves the only
#   read); the entry dies with the contract (Contract `dependent: :destroy`);
# - the template reference is a real FK with the default RESTRICT behaviour,
#   so a template version that is in use can never be deleted from under its
#   entries; `template_version` is a copy of the version number at the time of
#   entry, kept for reading without a join;
# - `values` holds the NON-personal field values as JSON;
# - `personal_values` is a TEXT column holding the personal field values. The
#   model encrypts it with Active Record Encryption (non-deterministic), so the
#   column never contains plaintext. The host must configure the encryption
#   keys (docs/contract-templates.md);
# - the creator is a plain bigint reference with NO foreign key and NO index
#   (the `decidim_author_id` precedent).
class CreateDecidimContractsSkContractTemplateEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_contract_template_entries do |t|
      t.references :contract, null: false, index: false,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts }
      t.references :contract_template, null: false,
                                       foreign_key: { to_table: :decidim_contracts_sk_contract_templates },
                                       index: { name: "idx_contracts_sk_template_entries_on_template_id" }
      t.integer :template_version, null: false
      t.json :values, null: false, default: {}
      t.text :personal_values
      t.string :internal_number
      t.references :decidim_created_by, null: true, index: false
      t.datetime :last_generated_at
      t.timestamps
    end

    add_index :decidim_contracts_sk_contract_template_entries, :contract_id,
              unique: true,
              name: "idx_contracts_sk_template_entries_unique_contract"
  end
end
