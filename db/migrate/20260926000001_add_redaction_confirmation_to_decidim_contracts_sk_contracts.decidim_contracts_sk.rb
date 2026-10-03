# frozen_string_literal: true

# Adds the ADR-007 privacy-redaction confirmation stamp to the engine's
# contracts table (civora-org/civora-platform#91): the nullable
# `redaction_confirmed_at` datetime records WHEN an editor last confirmed —
# on the contract's edit page — that personal data was redacted from the
# record and its documents, the hard precondition of the publish transition
# (enforced inside TransitionContract's lock) and of amendment publication
# (PublishAmendment's fail-closed backstop).
#
# Additive and nullable on purpose, mirroring the import-provenance
# migration: nothing backfills — pre-#91 records simply lack the stamp and
# therefore cannot publish until an editor confirms — and no default is set
# (a fabricated stamp would defeat the gate). The column is a system field:
# written only by the ConfirmRedaction command inside the contract row's
# lock, never form-writable.
class AddRedactionConfirmationToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contracts, :redaction_confirmed_at, :datetime
  end
end
