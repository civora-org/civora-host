# frozen_string_literal: true

# Creates the engine's contract links table (M01-87,
# civora-org/civora-platform#87): the join between a contract record and a
# platform-level project/result entity.
#
# Constraint policy mirrors the engine's precedents:
# - the contract reference is a real FK onto the contracts table — links are
#   record content and die with the contract (Contract declares
#   `dependent: :destroy`);
# - the polymorphic target carries NO FK on purpose (the AuditEvent
#   precedent): a target of another engine/host module may disappear, and a
#   dangling link is a legal, editor-cleanable state (the admin surface
#   flags it);
# - no organization column — tenancy derives through the contract, exactly
#   like parties/documents (unlike AuditEvent, whose trail must outlive its
#   target and therefore stores tenancy explicitly).
#
# The unique composite index enforces one link per (contract, target) pair.
# Its leading contract_id column also serves plain contract_id lookups, so
# the references lines suppress the redundant single-column indexes. The
# name is explicit, following the engine's "idx_contracts_sk_*" convention,
# and kept within PostgreSQL's 63-byte identifier limit.
class CreateDecidimContractsSkContractLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_contract_links do |t|
      t.references :contract, null: false, index: false,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts }
      # t.references derives target_type (string) and target_id (bigint); no
      # FK is possible — or wanted — for a polymorphic target.
      t.references :target, polymorphic: true, null: false, index: false
      t.timestamps
    end

    add_index :decidim_contracts_sk_contract_links, %i[contract_id target_type target_id],
              unique: true,
              name: "idx_contracts_sk_contract_links_on_contract_and_target"
  end
end
