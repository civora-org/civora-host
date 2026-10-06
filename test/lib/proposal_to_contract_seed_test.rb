# frozen_string_literal: true

require "test_helper"
require "rake"
require "support/participation_link_helpers"
require "decidim/proposals/test/factories"

# civora-org/civora-platform#132: the idempotent demo seed that builds the
# trail proposal -> budget project -> accountability result -> contract.
class ProposalToContractSeedTest < ActiveSupport::TestCase
  include ParticipationLinkHelpers

  COUNTED = [
    Decidim::ParticipatoryProcess, Decidim::ParticipatoryProcessStep, Decidim::Component, Decidim::User,
    Decidim::Proposals::Proposal, Decidim::Budgets::Budget, Decidim::Budgets::Project,
    Decidim::Accountability::Status, Decidim::Accountability::Result, Decidim::Accountability::Milestone,
    Decidim::ResourceLink, Decidim::ContractsSk::Contract, Decidim::ContractsSk::Party,
    Decidim::ContractsSk::ContractLink
  ].freeze

  setup do
    @organization = FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")
  end

  test "builds the whole story in one published participatory process" do
    outcome = CivoraDemo::ProposalToContract.call(@organization)

    assert outcome.space.published?
    assert_equal [outcome.space], [outcome.proposal, outcome.project, outcome.result].map(&:participatory_space).uniq

    assert_equal "accepted", outcome.proposal.proposal_state.token
    assert_predicate outcome.proposal, :published_state?
    assert_includes translated(outcome.proposal.answer), "prijatý"

    assert_equal [outcome.proposal], outcome.project.linked_resources(:proposals, "included_proposals").to_a
    assert_equal [outcome.proposal], outcome.result.linked_resources(:proposals, "included_proposals").to_a
    assert_equal [outcome.project], outcome.result.linked_resources(:projects, "included_projects").to_a

    assert_equal 100, outcome.result.progress
    assert_equal "Realizované", translated(outcome.result.status.name)
    assert_equal 3, outcome.result.milestones.count

    assert_predicate outcome.contract, :published?
    assert_equal "DEMO-2026-010", outcome.contract.reference
    assert_equal [%w(Decidim::Accountability::Result), %w(Decidim::Budgets::Project)],
                 [outcome.contract.links.where(target_type: "Decidim::Accountability::Result").pluck(:target_type),
                  outcome.contract.links.where(target_type: "Decidim::Budgets::Project").pluck(:target_type)]
    assert_equal %w(contractor object), outcome.contract.parties.pluck(:role).sort
    assert_predicate outcome.contract.crz_published_on, :present?
  end

  test "the contract links resolve to the result and the project of the story" do
    outcome = CivoraDemo::ProposalToContract.call(@organization)

    infos = outcome.contract.links.map { |link| Decidim::ContractsSk.resolve_link_target(link) }

    assert_equal 2, infos.compact.size
    assert_equal ["Nové detské ihrisko pri materskej škole"], infos.pluck(:label).uniq
    assert_equal [CivoraDemo::ProposalToContract.path_for(outcome.result),
                  CivoraDemo::ProposalToContract.path_for(outcome.project.budget, outcome.project)].sort, infos.pluck(:url).sort
  end

  test "a second run changes nothing" do
    first = CivoraDemo::ProposalToContract.call(@organization)
    counts = COUNTED.index_with(&:count)
    link_ids = Decidim::ResourceLink.order(:id).pluck(:id)

    second = CivoraDemo::ProposalToContract.call(@organization)

    assert_equal counts, COUNTED.index_with(&:count)
    assert_equal link_ids, Decidim::ResourceLink.order(:id).pluck(:id), "links must not be deleted and recreated"
    assert_empty second.created
    assert_equal [first.space, first.proposal, first.project, first.result, first.contract],
                 [second.space, second.proposal, second.project, second.result, second.contract]
  end

  test "keeps links an admin added by hand" do
    outcome = CivoraDemo::ProposalToContract.call(@organization)
    other = FactoryBot.create(:proposal, component: outcome.proposal.component)
    outcome.result.link_resources([outcome.proposal, other], "included_proposals")

    CivoraDemo::ProposalToContract.call(@organization)

    assert_equal [outcome.proposal, other].map(&:id).sort,
                 outcome.result.linked_resources(:proposals, "included_proposals").pluck(:id).sort
  end

  test "leaves an existing DEMO-2026-010 as it is, only linking it and filling the missing parties and CRZ filing" do
    author = FactoryBot.create(:user, :confirmed, organization: @organization)
    existing = Decidim::ContractsSk::Contract.create!(
      organization: @organization, author: author, reference: "DEMO-2026-010", state: "published",
      title: "Ručne upravený názov", amount: BigDecimal("1234.50"), published_at: Time.zone.local(2026, 9, 1, 12)
    )
    existing.parties.create!(role: "contractor", name: "Vlastný dodávateľ s.r.o.", ico: "00000099")

    outcome = CivoraDemo::ProposalToContract.call(@organization)

    assert_equal existing, outcome.contract
    existing.reload
    assert_equal ["Ručne upravený názov", BigDecimal("1234.50")], [existing.title, existing.amount]
    assert_equal ["Vlastný dodávateľ s.r.o."], existing.parties.where(role: "contractor").pluck(:name)
    assert_equal 1, existing.parties.where(role: "object").count
    assert_equal Date.new(2026, 9, 1), existing.crz_published_on
    assert_equal 2, existing.links.count
  end

  test "the rake task prints the URL of every step and can be run twice" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("civora:demo:proposal_to_contract")
    task = Rake::Task["civora:demo:proposal_to_contract"]

    first, = capture_io { task.invoke(@organization.id.to_s) }
    task.reenable
    second, = capture_io { task.invoke(@organization.id.to_s) }

    %w(Proces Návrh Projekt Výsledok Zmluva Dodávateľ Štatistika).each { |label| assert_includes first, label }
    assert_includes first, "http://#{@organization.host}/contracts/statistics"
    assert_match(%r{/contracts/suppliers/00000011}, first)
    assert_includes second, "Nothing new"
  end

  private

  def translated(hash)
    hash["sk"] || hash.values.first
  end
end
