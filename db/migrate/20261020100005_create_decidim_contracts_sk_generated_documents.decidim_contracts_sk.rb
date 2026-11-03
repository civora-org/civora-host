# frozen_string_literal: true

# Creates the table of documents generated from a template entry
# (civora-org/civora-platform#211, step P1). Admin-only by design: these are
# not the public Document records. A generated file reaches the public
# catalogue only when a reviewer-confirmed publication PDF is promoted to a
# Document (`promoted_document_id`), in a later step.
#
# Additive and reversible (`change` creates one table, `down` drops it). No
# backfill.
#
# - the contract and the entry are real FKs; both parents destroy their
#   generated documents first (`dependent: :destroy`);
# - `promoted_document_id` is a nullable FK onto the existing documents table
#   with ON DELETE SET NULL: removing the public document must not block
#   deleting a contract, and the generated record simply loses the link;
# - `variant` (internal/publication), `file_format` (docx/pdf) and `status`
#   (current/superseded) are plain strings validated by the model;
# - the generator is a plain bigint reference with NO foreign key and NO
#   index (the `decidim_author_id` precedent);
# - one index (contract, variant, file_format, status) serves the only read,
#   "the current file of this kind for this contract".
class CreateDecidimContractsSkGeneratedDocuments < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_generated_documents do |t|
      t.references :contract, null: false, index: false,
                              foreign_key: { to_table: :decidim_contracts_sk_contracts }
      t.references :entry, null: false,
                           foreign_key: { to_table: :decidim_contracts_sk_contract_template_entries },
                           index: { name: "idx_contracts_sk_generated_documents_on_entry_id" }
      t.string :variant, null: false
      t.string :file_format, null: false
      t.string :status, null: false, default: "current"
      t.string :checksum
      t.references :decidim_generated_by, null: true, index: false
      t.datetime :generated_at, null: false
      t.integer :template_version, null: false
      t.references :promoted_document, null: true, index: false,
                                       foreign_key: { to_table: :decidim_contracts_sk_documents,
                                                      on_delete: :nullify }
      t.timestamps
    end

    add_index :decidim_contracts_sk_generated_documents,
              %i[contract_id variant file_format status],
              name: "idx_contracts_sk_generated_documents_lookup"
  end
end
