# frozen_string_literal: true

# Creates the table of CRZ attachment links mirrored onto CRZ-mirrored
# contracts (civora-org/civora-platform#189). Link only: a row holds
# metadata and the CRZ file name, never the file itself (CRZ stays the
# source of truth; a removal upstream removes the row on the next sync).
#
# Constraint policy mirrors the engine's child tables (parties, links):
# - a real FK onto the contracts table (Contract declares
#   `dependent: :destroy`); no organization column, tenancy derives through
#   the contract;
# - `kind` is "text" (the text version, CRZ `file_name`) or "scan" (the scan,
#   `scan_file_name`); an attachment with both produces two rows;
# - `file_name` is NOT NULL and only ever holds a name that passed the
#   strict allowlist (CrzImport::AttachmentUrl); the public URL is built from
#   it at render time, so no URL is stored;
# - `title` is optional and clipped to 255; `file_size` and `changed_at` are
#   optional because CRZ often omits them;
# - one index on the contract serves the only read (one contract's list).
#
# Reversible with a single `change`: down drops the table.
class CreateDecidimContractsSkCrzAttachments < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_crz_attachments do |t|
      t.references :contract, null: false, index: true,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts }
      t.string :crz_id
      t.string :title
      t.string :kind, null: false
      t.string :file_name, null: false
      t.bigint :file_size
      t.datetime :changed_at
      t.timestamps
    end
  end
end
