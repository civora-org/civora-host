# frozen_string_literal: true

# Adds the CRZ filing confirmation to the engine's contracts table
# (civora-org/civora-platform#125): an editor who has filed an editorial
# record in the CRZ by hand records the round trip here, after the engine
# has verified the official record through the ekosystem feed.
#
# Three nullable system columns, written only by Admin::ConfirmCrzFiling
# inside the row lock and never form-writable (like redaction_confirmed_at
# and review_reason):
# - `crz_filed_at` (datetime): WHEN the filing was confirmed. Its presence
#   is the "filed" flag — it replaces the interim `crz_url` proxy of the
#   #124 deadline tracking and is the marker the CRZ sync reads to treat
#   the editorial record as the already-linked canonical record of its
#   CRZ id (no mirror, no collision).
# - `crz_published_on` (date): the publication date CRZ reports for the
#   record; nil when CRZ carried none (sentinel or blank).
# - `crz_filing_reason` (string, 1000): the editor's reason when the
#   confirmation overrode a mismatch between the editorial record and the
#   CRZ record; nil for a clean match.
#
# Additive, reversible (single `change`), nothing backfilled: records
# recorded by hand before this migration (a typed crz_url) stay
# "not confirmed as filed" on purpose — only a verified confirmation may
# count as filed. No defaults, no indexes (read per record, never queried
# as a set apart from the deadline scope's NULL test on a small table).
#
# Hosts that already ran the engine migrations under their original
# timestamps copy this file verbatim (README: "install:migrations"
# paragraph and the host's "Upgrading the engine" procedure).
class AddCrzFilingToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contracts, :crz_filed_at, :datetime
    add_column :decidim_contracts_sk_contracts, :crz_published_on, :date
    add_column :decidim_contracts_sk_contracts, :crz_filing_reason, :string, limit: 1000
  end
end
