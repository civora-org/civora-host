# frozen_string_literal: true

# Adds the amendment lifecycle to the engine's amendments table
# (M02-05-B, civora-org/civora-platform#65, ADR-006).
#
# All columns are additive and nullable except `state`:
# - `state` carries the amendment lifecycle (draft -> published only). The
#   default backfills every existing row to "draft", which is the correct
#   semantic for rows predating the lifecycle: nothing was ever published
#   before #65, so no row can already be immutable. Plain add_column
#   defaults are applied to existing rows by both PostgreSQL (hosts) and
#   SQLite (the :db spec harness), so no explicit backfill is needed.
# - `published_at` is a SYSTEM field: it is stamped by PublishAmendment at
#   the publish event and is never form-writable (the contract's own
#   published_at doctrine, #75).
# - `decidim_organization_id` / `decidim_author_id` follow the contracts
#   table's explicit tenancy/actor pattern (t.references with real FKs).
#   They are added NULLABLE on purpose: a NOT NULL add_column cannot serve
#   pre-migration rows without inventing FK values for them, and copying
#   the parent contract's author would fabricate provenance. The Amendment
#   model requires both through belongs_to, so every engine write path
#   (CreateAmendment) is still forced to carry them.
# - `content_snapshot` is the #65 DECISION: a single JSON column holding
#   the frozen contract content-field hash taken at publish time (keys =
#   the data-dictionary content fields), so a published amendment never
#   changes when the contract's live fields do.
#
# The organization index name is explicit, following the engine's
# "idx_contracts_sk_*" convention; the author index uses the Rails default
# (within PostgreSQL's 63-byte limit), mirroring the contracts migration.
class AddAmendmentLifecycleToDecidimContractsSkAmendments < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_amendments, :state, :string, null: false, default: "draft"
    add_column :decidim_contracts_sk_amendments, :published_at, :datetime
    add_reference :decidim_contracts_sk_amendments, :decidim_organization,
                  type: :bigint,
                  foreign_key: { to_table: :decidim_organizations },
                  index: { name: "idx_contracts_sk_amendments_on_organization_id" }
    add_reference :decidim_contracts_sk_amendments, :decidim_author,
                  type: :bigint,
                  foreign_key: { to_table: :decidim_users },
                  index: true
    add_column :decidim_contracts_sk_amendments, :content_snapshot, :json
  end
end
