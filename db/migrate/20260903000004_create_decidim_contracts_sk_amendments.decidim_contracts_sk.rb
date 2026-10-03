# frozen_string_literal: true

# Creates the engine's contract amendments table (M02-02-C,
# civora-org/civora-platform#57).
#
# Minimal constraints: an amendment is a numbered revision of its contract —
# (contract_id, version) is unique, and the contract reference is a real FK
# constraint. Amendment immutability and the version sequence behaviour are
# deferred to M02-05-B (civora-org/civora-platform#65).
#
# The composite unique index's leading column also serves plain contract_id
# lookups, so the references line suppresses the redundant single-column
# index. Its name is explicit, following the engine's "idx_contracts_sk_*"
# convention, and kept within PostgreSQL's 63-byte identifier limit.
class CreateDecidimContractsSkAmendments < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_amendments do |t|
      t.references :contract, null: false, index: false,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts }
      t.integer :version, null: false
      t.string :summary, null: false
      t.timestamps
    end

    add_index :decidim_contracts_sk_amendments, %i[contract_id version],
              unique: true, name: "idx_contracts_sk_amendments_on_contract_id_and_version"
  end
end
