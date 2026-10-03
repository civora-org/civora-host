# frozen_string_literal: true

# Adds the import-provenance hardening to the engine's contracts table
# (civora-org/civora-platform#85): the nullable `checksum` column (the
# source-payload digest, ADR-008) and a composite index on
# (organization, source, source_id) — the idempotent upsert lookup for the
# future import arc.
#
# Both changes are additive and nullable: nothing backfills, and no
# behaviour attaches until the import arc consumes them. The index name is
# explicit — the Rails-generated name exceeds PostgreSQL's 63-byte
# identifier limit — and elides the middle `source` column to stay within
# the same limit (the fully spelled convention name would exceed it too).
class AddImportProvenanceToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contracts, :checksum, :string
    add_index :decidim_contracts_sk_contracts, %i[decidim_organization_id source source_id],
              name: "idx_contracts_sk_contracts_on_organization_id_and_source_id"
  end
end
