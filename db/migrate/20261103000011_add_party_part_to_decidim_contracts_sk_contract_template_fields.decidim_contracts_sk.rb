# frozen_string_literal: true

# Lets a contract template declare which of its fields form the counterparty
# of the contract (civora-org/civora-platform#211, follow-up: contract parties
# from the template entry).
#
# `party_part` is NULL for an ordinary field and one of "name", "ico",
# "address" for the field that holds that part of the counterparty. The
# import sets it from the sidecar's `counterparty` mapping. A counterparty
# whose name field is personal data is a natural person and is published only
# as "Fyzická osoba"; otherwise it is a company published with the name, IČO
# and seat typed in those fields.
#
# Additive and reversible (`change` adds one nullable string column). No
# backfill, no default, no index (read together with the template's fields).
# Templates imported earlier keep working: without a declared counterparty no
# counterparty party is created.
class AddPartyPartToDecidimContractsSkContractTemplateFields < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contract_template_fields, :party_part, :string
  end
end
