# frozen_string_literal: true

# CRZ import scope (civora-org/civora-platform#145): the engine mirrors only
# contracts whose parties carry the organization's IČO, read here from
# CRZ_ICO_ORG_<organization id> (e.g. CRZ_ICO_ORG_1=00313271). An
# organization without the variable is refused by the sync (fail closed),
# never imported unscoped. See docs/ops/crz-sync.md.
Decidim::ContractsSk.crz_organization_ico_resolver = lambda do |organization|
  ENV.fetch("CRZ_ICO_ORG_#{organization.id}", nil)
end
