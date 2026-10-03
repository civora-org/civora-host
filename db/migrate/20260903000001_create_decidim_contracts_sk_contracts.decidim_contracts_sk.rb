# frozen_string_literal: true

# Creates the engine's contract records table (M02-02-A,
# civora-org/civora-platform#55).
#
# Editorial skeleton only: identity, lifecycle state, and the manual
# CRZ-handoff provenance columns (rationale in docs/contracts-domain-notes.md).
# Functional fields (subject matter, amounts, dates, parties, documents,
# amendments) arrive as additive migrations in downstream milestones.
#
# Composite index names are explicit: the Rails-generated names for these
# indexes exceed PostgreSQL's 63-byte identifier limit.
class CreateDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_contracts do |t|
      t.references :decidim_organization, null: false, index: { name: "idx_contracts_sk_contracts_on_organization_id" }
      t.references :decidim_author, null: false, index: true
      t.string :title, null: false
      t.string :reference, null: false
      t.string :state, null: false, default: "draft"
      # Manual CRZ-handoff provenance (docs/contracts-domain-notes.md); no
      # behavior until the V0.2 import arc.
      t.string :source, null: false, default: "editorial"
      t.string :source_id
      t.datetime :imported_at
      t.string :import_status
      t.timestamps
    end

    add_index :decidim_contracts_sk_contracts, %i[decidim_organization_id reference],
              unique: true, name: "idx_contracts_sk_contracts_on_organization_id_and_reference"
    add_index :decidim_contracts_sk_contracts, %i[decidim_organization_id state],
              name: "idx_contracts_sk_contracts_on_organization_id_and_state"
  end
end
