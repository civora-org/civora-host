# frozen_string_literal: true

# CRZ import scope (civora-org/civora-platform#145): the engine mirrors only
# contracts whose parties carry the organization's IČO, read here from
# CRZ_ICO_ORG_<organization id> (e.g. CRZ_ICO_ORG_1=00313271). An
# organization without the variable is refused by the sync (fail closed),
# never imported unscoped. See docs/ops/crz-sync.md.
Decidim::ContractsSk.crz_organization_ico_resolver = lambda do |organization|
  ENV.fetch("CRZ_ICO_ORG_#{organization.id}", nil)
end

# Participation link (civora-org/civora-platform#130, ADR-009): contracts can
# be linked to Decidim Accountability results and Budgets projects. The
# resolver (app/lib/participation_link_resolver.rb) is organization-scoped and
# fails closed. The lambda defers to the constant so code reloading in
# development stays safe (an initializer must not touch an autoloaded
# constant directly). Keep the type list in sync with
# ParticipationLinkResolver::TARGET_TYPES; a test pins it. See docs/ops/participation-link.md.
Decidim::ContractsSk.supported_link_target_types = %w(Decidim::Accountability::Result Decidim::Budgets::Project)
Decidim::ContractsSk.link_target_resolver = ->(link) { ParticipationLinkResolver.call(link) }
