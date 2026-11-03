# frozen_string_literal: true

# Creates the per-organization counters behind internal contract numbers
# (civora-org/civora-platform#211, step P1). One row per (organization,
# scope_key); a scope key such as "zmluvy:2026" gives a yearly sequence.
#
# Additive and reversible (`change` creates one table, `down` drops it). No
# backfill: a counter row is created on first use.
#
# - the unique (organization, scope_key) index is what makes "create the row
#   on first use" safe under concurrency: the loser of the race gets
#   RecordNotUnique and re-reads;
# - `last_value` is the last number handed out (0 = none yet); the model
#   increments it under a row lock (ReferenceCounter#next!).
class CreateDecidimContractsSkReferenceCounters < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_reference_counters do |t|
      t.references :decidim_organization, null: false, index: false,
                                          foreign_key: { to_table: :decidim_organizations }
      t.string :scope_key, null: false
      t.bigint :last_value, null: false, default: 0
      t.timestamps
    end

    add_index :decidim_contracts_sk_reference_counters,
              %i[decidim_organization_id scope_key],
              unique: true,
              name: "idx_contracts_sk_reference_counters_unique_scope"
  end
end
