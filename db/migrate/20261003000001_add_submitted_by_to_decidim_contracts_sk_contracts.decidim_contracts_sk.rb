# frozen_string_literal: true

# Adds the four-eyes submitter stamp to the engine's contracts table
# (civora-org/civora-platform#123): the nullable `decidim_submitted_by_id`
# records WHICH person last submitted the record for review. The
# four-eyes rule reads it — the person who last submitted a contract may
# not return, approve or reject it (Permissions + TransitionContract; the
# default role resolver gives org admins both engine roles, so the role
# split alone never separated duties per person). It is written only by
# TransitionContract on every `submit` edge (first submit and resubmit
# from returned alike), inside the row lock, and is never form-writable.
#
# Shape, mirroring `decidim_author_id` of the base migration: a plain
# bigint reference column with NO foreign-key constraint (a deleted user
# must not block or cascade into the record; a dangling id simply matches
# nobody) and NO index — the stamp is read per record, never queried as a
# set, so an index would only cost writes.
#
# Backfill (Gate-1 decision D2-B): records already in review when this
# migration runs would otherwise carry a nil stamp and slip the rule
# ("legacy nil is not blocked"). The audit trail knows better, so the up
# direction stamps each record with the actor of its MOST RECENT
# `contract.submit` audit row (ORDER BY created_at DESC, id DESC, the id
# as the deterministic tiebreaker). Records with no submit audit row keep
# nil and are not even rewritten (outer WHERE EXISTS). One correlated subquery of plain SQL, portable across PostgreSQL
# and SQLite. The down direction needs no data step: removing the column
# removes the stamps with it.
#
# Hosts that already ran the engine migrations under their original
# timestamps copy this file verbatim (README: "install:migrations"
# paragraph and the host's "Upgrading the engine" procedure) instead of
# re-running install:migrations.
class AddSubmittedByToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_reference :decidim_contracts_sk_contracts, :decidim_submitted_by, null: true, index: false

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE decidim_contracts_sk_contracts
          SET decidim_submitted_by_id = (
            SELECT audit.decidim_user_id
            FROM decidim_contracts_sk_audit_events audit
            WHERE audit.action = 'contract.submit'
              AND audit.target_type = 'Decidim::ContractsSk::Contract'
              AND audit.target_id = decidim_contracts_sk_contracts.id
            ORDER BY audit.created_at DESC, audit.id DESC
            LIMIT 1
          )
          WHERE EXISTS (
            SELECT 1
            FROM decidim_contracts_sk_audit_events audit
            WHERE audit.action = 'contract.submit'
              AND audit.target_type = 'Decidim::ContractsSk::Contract'
              AND audit.target_id = decidim_contracts_sk_contracts.id
          )
        SQL
      end
    end
  end
end
