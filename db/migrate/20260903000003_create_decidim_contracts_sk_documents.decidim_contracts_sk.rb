# frozen_string_literal: true

# Creates the engine's contract documents table (M02-02-B,
# civora-org/civora-platform#56).
#
# Metadata only: file_name/content_type/file_size describe the future
# attachment ahead of the upload/validation arc (M02-05-A,
# civora-org/civora-platform#64) — no behaviour attaches to them until then.
# The kind column defaults to "contract", the catalogue's default type.
class CreateDecidimContractsSkDocuments < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_documents do |t|
      t.references :contract, null: false,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts },
                              index: { name: "idx_contracts_sk_documents_on_contract_id" }
      t.string :title, null: false
      t.string :kind, null: false, default: "contract"
      # Nullable file metadata (no behaviour until M02-05-A).
      t.string :file_name
      t.string :content_type
      t.integer :file_size
      t.timestamps
    end
  end
end
