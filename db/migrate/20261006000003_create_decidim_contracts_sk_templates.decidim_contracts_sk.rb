# frozen_string_literal: true

# Creates the engine's contract templates table (civora-org/civora-platform
# #127): organization-scoped defaults an editor starts a contract draft from.
#
# A template stores the title pattern, subject matter and currency defaults
# and ONE party skeleton (the object party, typically the municipality with
# its IČO), flattened into three `object_party_*` columns: the contractor is
# contract-specific by nature and is never templated, so a child table would
# model a generality nothing uses. Copy-on-create: a contract copies these
# values when it is created and keeps no reference back to the template, so
# there is deliberately no template column on the contracts table and no
# foreign key into this one; editing or removing a template never touches a
# contract.
#
# Constraint policy mirrors the engine's precedents:
# - the organization is a plain bigint reference with NO foreign key (the
#   contracts table's `decidim_organization_id` precedent); tenancy is also
#   the leading column of the unique (organization, name) index, which serves
#   the only reads (the org's list ordered by name), so the reference itself
#   carries no separate index;
# - no author/creator column: nobody needs to know who typed a template, and
#   the engine avoids storing personal data it does not use.
#
# Reversible with a single `change`: down drops the table (the templates
# only; every contract created from one is unaffected).
class CreateDecidimContractsSkTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_templates do |t|
      t.references :decidim_organization, null: false, index: false
      t.string :name, null: false
      t.string :title_pattern
      t.text :subject_matter
      t.string :currency, null: false, default: "EUR"
      t.string :object_party_name
      t.string :object_party_ico
      t.string :object_party_address
      t.timestamps
    end

    add_index :decidim_contracts_sk_templates, %i[decidim_organization_id name],
              unique: true, name: "idx_contracts_sk_templates_on_organization_id_and_name"
  end
end
