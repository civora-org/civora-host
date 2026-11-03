# frozen_string_literal: true

# Adds the optional agreed later effectiveness date
# (civora-org/civora-platform#202, § 47a ods. 2 OZ: the parties may agree that
# a contract that must be published in the CRZ takes effect later than the
# day after publication).
#
# One nullable date column, no default, no index (never filtered in SQL: the
# effectiveness status is derived in Ruby, see CrzDeadline.effectiveness).
# Distinct from the existing effective_from, which is the contract's own
# (possibly retroactive) effective date as typed by the editor and drives
# nothing. Existing rows stay NULL, which means "no later date agreed".
#
# The version is dated on the day it was written, never in the future: Rails
# 7.2 refuses a schema whose migrations are dated more than a day ahead
# (see spec/decidim/contracts_sk/migration_timestamps_spec.rb).
#
# Reversible: down drops the column (any agreed dates entered since are lost).
class AddAgreedEffectiveOnToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contracts, :agreed_effective_on, :date
  end
end
