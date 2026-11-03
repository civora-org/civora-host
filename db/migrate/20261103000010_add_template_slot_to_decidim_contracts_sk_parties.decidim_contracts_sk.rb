# frozen_string_literal: true

# Marks the parties a contract template creates for itself
# (civora-org/civora-platform#211, follow-up: contract parties from the
# template entry).
#
# `template_slot` is NULL for every party a person adds by hand (and for every
# existing row). The contract-from-template command sets it to "municipality"
# or "counterparty" on the two parties it creates, so that generating the
# documents again finds and updates exactly those rows (no duplicates) and
# never touches a manually added party.
#
# Additive and reversible (`change`: one nullable string column and one unique
# index). No backfill, no default. The unique index covers only rows with a
# slot: NULLs are distinct in a unique index on both PostgreSQL and SQLite, so
# any number of manual parties may share a contract, while at most one party
# per slot may exist (a race between two regenerations fails loudly instead of
# duplicating). The index name is explicit and within PostgreSQL's 63-byte
# identifier limit.
class AddTemplateSlotToDecidimContractsSkParties < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_parties, :template_slot, :string
    add_index :decidim_contracts_sk_parties, %i[contract_id template_slot],
              unique: true, name: "idx_contracts_sk_parties_on_contract_id_and_slot"
  end
end
