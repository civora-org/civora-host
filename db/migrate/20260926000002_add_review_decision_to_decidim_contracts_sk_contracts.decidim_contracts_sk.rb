# frozen_string_literal: true

# Adds the reviewer decision reason to the engine's contracts table
# (civora-org/civora-platform#90): the nullable `review_reason` string
# (capped at 1000 characters) records WHY a reviewer returned or rejected
# the record, and the nullable `reviewed_at` datetime records WHEN the
# decision was made. Both are written only by TransitionContract on the
# return/reject edges, inside the row lock — the reason, the decision
# timestamp, the state change and the audit row commit atomically.
#
# Additive and nullable on purpose, mirroring the redaction-confirmation
# migration: nothing backfills — pre-#90 records simply carry no decision
# text — and no default is set (a fabricated judgment would defeat the
# gate). The columns are system fields: `submit` from `returned` clears
# both (the resubmit clears the stale reason), and they are never
# form-writable.
class AddReviewDecisionToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contracts, :review_reason, :string, limit: 1000
    add_column :decidim_contracts_sk_contracts, :reviewed_at, :datetime
  end
end
