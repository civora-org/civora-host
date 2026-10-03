# frozen_string_literal: true

# Creates the engine's contract parties table (M02-02-B,
# civora-org/civora-platform#56).
#
# Minimal constraints: parties are contract-scoped — the contract reference
# is a real FK constraint, and tenancy is derived through the contract's
# organization (no organization foreign key on this table).
#
# The composite index's leading column also serves plain contract_id lookups,
# so the references line suppresses the redundant single-column index. Its
# name is explicit, following the engine's "idx_contracts_sk_*" convention,
# and kept within PostgreSQL's 63-byte identifier limit.
class CreateDecidimContractsSkParties < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_parties do |t|
      t.references :contract, null: false, index: false,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts }
      t.string :role, null: false
      t.string :name, null: false
      # Optional fixed-length company identifier; the model validates the
      # 8-digit format, the DB only carries the limit.
      t.string :ico, limit: 8
      t.string :address
      t.timestamps
    end

    add_index :decidim_contracts_sk_parties, %i[contract_id role],
              name: "idx_contracts_sk_parties_on_contract_id_and_role"
  end
end
