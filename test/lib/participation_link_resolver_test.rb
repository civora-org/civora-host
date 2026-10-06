# frozen_string_literal: true

require "test_helper"
require "support/participation_link_helpers"

# civora-org/civora-platform#130: the host resolver behind the engine's
# link_target_resolver seam. Organization scoping and public visibility are
# the host's responsibility (engine README, Configuration).
class ParticipationLinkResolverTest < ActiveSupport::TestCase
  include ParticipationLinkHelpers

  setup do
    @tenant = build_tenant
    @result = create_result(@tenant)
    @contract = create_contract(@tenant)
  end

  test "the initializer wires the whitelist and the resolver into the engine" do
    assert_equal ParticipationLinkResolver::TARGET_TYPES.sort, Decidim::ContractsSk.supported_link_target_types.sort
    assert_equal %w(Decidim::Accountability::Result Decidim::Budgets::Project), ParticipationLinkResolver::TARGET_TYPES
  end

  test "resolves a result of the contract's organization to a label and a relative path" do
    info = Decidim::ContractsSk.resolve_link_target(link!(@contract, @result))

    assert_equal translated(@result.title), info[:label]
    assert_equal "/processes/#{@tenant[:space].slug}/f/#{@result.component.id}/results/#{@result.id}", info[:url]
  end

  test "resolves a budgets project to a path nested under its budget" do
    project = create_project(@tenant)
    info = Decidim::ContractsSk.resolve_link_target(link!(@contract, project))

    assert_equal translated(project.title), info[:label]
    assert_equal "/processes/#{@tenant[:space].slug}/f/#{project.component.id}/budgets/#{project.budget.id}/projects/#{project.id}", info[:url]
  end

  test "a result of another organization never resolves" do
    foreign = create_result(build_tenant)

    assert_nil Decidim::ContractsSk.resolve_link_target(link!(@contract, foreign))
  end

  test "a project of another organization never resolves" do
    foreign = create_project(build_tenant)

    assert_nil Decidim::ContractsSk.resolve_link_target(link!(@contract, foreign))
  end

  test "an unpublished component, an unpublished space and a private space do not resolve" do
    link = link!(@contract, @result)

    @result.component.update!(published_at: nil)
    assert_nil Decidim::ContractsSk.resolve_link_target(link)
    @result.component.update!(published_at: Time.current)
    assert Decidim::ContractsSk.resolve_link_target(link.reload)

    @tenant[:space].update!(private_space: true)
    assert_nil Decidim::ContractsSk.resolve_link_target(link.reload)
    @tenant[:space].update!(private_space: false, published_at: nil)
    assert_nil Decidim::ContractsSk.resolve_link_target(link.reload)
  end

  test "a dangling (deleted) target and an unsupported type do not resolve" do
    link = link!(@contract, @result)
    @result.really_destroy!
    assert_nil Decidim::ContractsSk.resolve_link_target(link.reload)

    other = @contract.links.create!(target_type: "Decidim::Organization", target_id: @tenant[:organization].id)
    assert_nil Decidim::ContractsSk.resolve_link_target(other)
  end

  private

  def translated(hash)
    hash[I18n.locale.to_s].presence || hash.values.first
  end
end
