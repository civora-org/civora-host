# frozen_string_literal: true

# Creates the engine's internal review notes table (civora-org/civora-platform
# #128): a private, append-only discussion thread per contract, visible only
# to role holders in the admin.
#
# Constraint policy mirrors the engine's precedents:
# - the contract reference is a real FK onto the contracts table: notes die
#   with their contract (Contract declares `dependent: :delete_all`, which
#   bypasses the append-only model guard on purpose);
# - the author is a plain bigint reference with NO foreign key and NO index
#   (the `decidim_author_id` / `decidim_submitted_by_id` precedent): a deleted
#   user must not block or cascade into the thread, and the thread is never
#   queried by author;
# - no organization column: tenancy derives through the contract, like
#   parties/documents/links;
# - only `created_at`: the table is append-only, so there is no `updated_at`
#   to maintain. The composite index (contract, id) serves the only read, the
#   chronological thread of one contract.
#
# Reversible with a single `change`: down drops the table (and its notes).
class CreateDecidimContractsSkNotes < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_notes do |t|
      t.references :contract, null: false, index: false,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts }
      t.references :decidim_author, null: false, index: false
      t.text :body, null: false
      t.datetime :created_at, null: false
    end

    add_index :decidim_contracts_sk_notes, %i[contract_id id],
              name: "idx_contracts_sk_notes_on_contract_and_id"
  end
end
