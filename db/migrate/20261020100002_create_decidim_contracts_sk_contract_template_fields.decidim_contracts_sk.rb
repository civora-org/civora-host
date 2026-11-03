# frozen_string_literal: true

# Creates the field definitions of a contract template version
# (civora-org/civora-platform#211, step P1): the ordered list of merge fields
# the form will ask for and the generator will fill.
#
# Additive and reversible (`change` creates one table, `down` drops it). No
# backfill.
#
# - the template reference is a real FK; the unique (template, key) index
#   backs the model's uniqueness validation and also serves the only read
#   (one template's fields), so the reference's own index is suppressed;
# - `key` is the merge field name (ASCII snake_case, validated by the model);
# - `field_type` is a plain string validated by the model against the field
#   type vocabulary (text, long_text, date, money, number, person, org_header);
# - `personal_data` marks fields whose values are stored encrypted and
#   redacted in the publication copy; the model forces it on for `person`.
class CreateDecidimContractsSkContractTemplateFields < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_contract_template_fields do |t|
      t.references :contract_template, null: false, index: false,
                                       foreign_key: { to_table: :decidim_contracts_sk_contract_templates }
      t.string :key, null: false
      t.string :label, null: false
      t.string :field_type, null: false, default: "text"
      t.integer :position, null: false, default: 0
      t.boolean :required, null: false, default: false
      t.boolean :personal_data, null: false, default: false
      t.text :help_text
      t.string :group_key
      t.timestamps
    end

    add_index :decidim_contracts_sk_contract_template_fields,
              %i[contract_template_id key],
              unique: true,
              name: "idx_contracts_sk_template_fields_unique_key"
  end
end
