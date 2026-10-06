# frozen_string_literal: true

require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"
require "decidim/accountability/test/factories"
require "decidim/budgets/test/factories"

# Synthetic-data builders for the participation link tests: an organization
# with a published process, an accountability result, a budgets project and
# contracts linked to them. Fictional data only.
module ParticipationLinkHelpers
  def build_tenant
    organization = FactoryBot.create(:organization)
    space = FactoryBot.create(:participatory_process, organization: organization)
    author = FactoryBot.create(:user, :confirmed, organization: organization)
    { organization: organization, space: space, author: author }
  end

  def create_result(tenant, **attrs)
    component = FactoryBot.create(:accountability_component, participatory_space: tenant[:space])
    FactoryBot.create(:result, component: component, **attrs)
  end

  def create_project(tenant)
    component = FactoryBot.create(:budgets_component, participatory_space: tenant[:space])
    FactoryBot.create(:project, budget: FactoryBot.create(:budget, component: component))
  end

  def create_contract(tenant, state: "published", **attrs)
    @contract_serial = (@contract_serial || 0) + 1
    Decidim::ContractsSk::Contract.create!(
      { organization: tenant[:organization], author: tenant[:author], state: state,
        title: "Detske ihrisko #{@contract_serial}", reference: "TST-#{@contract_serial}-#{SecureRandom.hex(3)}",
        published_at: (state == "published" ? Time.current : nil) }.merge(attrs)
    )
  end

  def link!(contract, target)
    contract.links.create!(target_type: target.class.name, target_id: target.id)
  end
end
