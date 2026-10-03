# frozen_string_literal: true

# Adds the unique index on (organization, source_id) to the engine's
# contracts table (civora-org/civora-platform#86 review fold-in): the
# database-level backstop for the CRZ import's idempotent upsert — two
# concurrent imports of the same CRZ record can no longer both create a
# mirror row. The upsert command rescues ActiveRecord::RecordNotUnique and
# reroutes to the update/collision path, so the race winner is never
# stamped failed.
#
# NULL source_id is exempt everywhere: both PostgreSQL and SQLite treat
# NULLs as distinct in unique indexes, so editorial rows (source_id NULL —
# the overwhelmingly common case) are unaffected; unbounded NULL rows stay
# legal by design — the constraint binds only mirror records, which always
# carry the CRZ numeric id.
#
# The name is explicit (engine "idx_contracts_sk_*" convention) and stays
# within PostgreSQL's 63-byte identifier limit. Purely additive: no
# backfill, no behavior change for existing data (only the import writes
# non-NULL source_ids, and it already refuses duplicates).
class AddSourceIdUniqueIndexToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_index :decidim_contracts_sk_contracts, %i[decidim_organization_id source_id],
              name: "idx_contracts_sk_contracts_on_org_and_source_id_unique",
              unique: true
  end
end
