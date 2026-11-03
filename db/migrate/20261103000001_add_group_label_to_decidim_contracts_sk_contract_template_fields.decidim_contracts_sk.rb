# frozen_string_literal: true

# Adds a display heading for a field's group to the contract template fields
# (civora-org/civora-platform#211, P6).
#
# A field already has a required `label` (its caption in the form). What was
# missing is the heading of a GROUP of fields: `group_key` is an ASCII key
# (`kupujuci`), so headings with diacritics ("Kupujúci") had to come from a
# locale file keyed by the group, which a town cannot add to. `group_label`
# stores the heading on the fields of the group, set by the template import
# (sidecar `group_labels`). The form reads it first and falls back to the
# locale map and then the humanized key, so templates imported before this
# column keep rendering as they did.
#
# Additive and reversible (`change` adds one nullable string column). No
# backfill, no default, no index (never queried, only read with the field).
# A plain string, not a translated JSONB column: the engine has no translated
# columns, a template is written in one language, and the strings are the
# town's own wording.
class AddGroupLabelToDecidimContractsSkContractTemplateFields < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contract_template_fields, :group_label, :string
  end
end
