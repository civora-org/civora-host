# frozen_string_literal: true

# Adds the contract content fields to the engine's contracts table
# (M02-02-D, civora-org/civora-platform#75; the data dictionary's
# "Contract content" table, types finalized here by the owning milestone).
#
# All columns are additive and nullable except `currency`: the D1 allowlist
# (SUPPORTED_CURRENCIES on the model) is EUR-only for V0.1, so the column is
# NOT NULL with an "EUR" default. Plain add_column defaults are applied to
# existing rows by both PostgreSQL (hosts) and SQLite (the :db spec harness),
# so no backfill is needed for currency.
#
# `published_at` is a SYSTEM field: it is stamped by TransitionContract on
# the publish event and is never form-writable. Existing published rows (the
# host app carries live demo data) are backfilled from `updated_at` — the
# best available provenance for a publication time the engine did not yet
# record. The backfill needs no undo (the down path simply drops the
# columns), so it lives in the up arm of a reversible block; the IS NULL
# guard keeps the statement idempotent if it were ever replayed.
class AddContentFieldsToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
  def change
    add_column :decidim_contracts_sk_contracts, :subject_matter, :text
    add_column :decidim_contracts_sk_contracts, :amount, :decimal, precision: 12, scale: 2
    add_column :decidim_contracts_sk_contracts, :currency, :string, limit: 3, null: false, default: "EUR"
    add_column :decidim_contracts_sk_contracts, :signed_on, :date
    add_column :decidim_contracts_sk_contracts, :effective_from, :date
    add_column :decidim_contracts_sk_contracts, :published_at, :datetime
    add_column :decidim_contracts_sk_contracts, :crz_url, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE decidim_contracts_sk_contracts
          SET published_at = updated_at
          WHERE state = 'published' AND published_at IS NULL
        SQL
      end
    end
  end
end
