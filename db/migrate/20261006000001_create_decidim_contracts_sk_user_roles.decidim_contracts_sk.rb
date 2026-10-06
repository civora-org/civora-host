# frozen_string_literal: true

# Creates the engine's user roles table (M03-06-B,
# civora-org/civora-platform#109, parent #95): an organization-scoped grant of
# one engine role (ContractLifecycle::ROLES — editor, reviewer) to one Decidim
# user. Nothing reads it yet; the resolver union is a later sub-issue.
#
# Constraint policy mirrors the audit events precedent:
# - tenancy is explicit (decidim_organization_id) and both the user and the
#   organization are real FKs — a grant cannot dangle, and it carries no
#   personal data beyond the user reference;
# - `role` is a plain string validated by the model against the engine's role
#   vocabulary (no DB enum/check: the vocabulary lives in one Ruby constant);
# - the unique composite index enforces one grant per (user, organization,
#   role). Its leading user column also serves plain user lookups, so the user
#   reference suppresses the redundant single-column index. The organization
#   index is kept (lookups by tenant), with an explicit name because the Rails
#   default exceeds PostgreSQL's 63-byte identifier limit.
#
# Reversible: a single `change` with only DSL ActiveRecord can invert.
class CreateDecidimContractsSkUserRoles < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_contracts_sk_user_roles do |t|
      t.references :decidim_user, null: false, index: false,
                                  foreign_key: { to_table: :decidim_users }
      t.references :decidim_organization, null: false,
                                          foreign_key: { to_table: :decidim_organizations },
                                          index: { name: "idx_contracts_sk_user_roles_on_organization_id" }
      t.string :role, null: false
      t.timestamps
    end

    add_index :decidim_contracts_sk_user_roles,
              %i[decidim_user_id decidim_organization_id role],
              unique: true,
              name: "index_decidim_contracts_sk_user_roles_unique"
  end
end
