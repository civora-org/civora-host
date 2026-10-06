# frozen_string_literal: true

# Creates the e-mail alert subscriptions table (civora-org/civora-platform
# #121): a resident subscribes an address to a catalogue search and gets a
# digest of newly published contracts that match it.
#
# This is the engine's first table of resident personal data (an e-mail
# address), so the column list is the whole data-minimisation decision and
# nothing else is stored: no IP address, no user agent, no user reference
# (anonymous subscription, no account needed), no name, no click or open
# tracking.
#
# - decidim_organization_id: the tenant. A plain bigint with no foreign key
#   (the contracts table's precedent); it leads the lookup index below.
# - email: stored lower-cased and stripped; only ever used to send this
#   subscription's mails.
# - filter_params: the catalogue's normalized filter params
#   (CatalogueQuery#to_params minus the sort), JSON. Not a foreign key into
#   anything: the subscription keeps its own copy of the search.
# - locale: the language of its mails.
# - confirmed_at: NULL until the double opt-in link was used. Nothing is
#   sent to an unconfirmed row; such rows are purged after 48 hours.
# - last_notified_at: the end of the window already delivered; the next
#   digest covers contracts published after it, so no contract is mailed
#   twice. Set to confirmed_at on confirmation.
# - token_digest: SHA-256 hex of the random confirmation token. The raw
#   token only ever exists in the confirmation e-mail. (The unsubscribe link
#   is a signed id, so it needs no column.)
#
# Unsubscribing DELETES the row (no "unsubscribed" flag is kept).
#
# Reversible with a single `change`: down drops the table (the subscriptions
# only; no contract data is touched).
class CreateDecidimContractsSkSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_subscriptions do |t|
      t.references :decidim_organization, null: false, index: false
      t.string :email, null: false, limit: 254
      t.json :filter_params, null: false
      t.string :locale, null: false
      t.datetime :confirmed_at
      t.datetime :last_notified_at
      t.string :token_digest, null: false, limit: 64
      t.timestamps
    end

    add_index :decidim_contracts_sk_subscriptions, :token_digest,
              unique: true, name: "idx_contracts_sk_subscriptions_on_token_digest"
    add_index :decidim_contracts_sk_subscriptions, %i[decidim_organization_id email],
              name: "idx_contracts_sk_subscriptions_on_organization_id_and_email"
  end
end
