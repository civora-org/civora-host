# frozen_string_literal: true

require "test_helper"
require "rake"
require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"
require "decidim/participatory_processes/test/factories"

# Participation entry points: the header link and the hero CTA appear only when
# the organization has a process a visitor can open; the homepage block is added
# by an idempotent rake task (docs/ops/participation-navigation.md).
class ParticipationNavigationTest < ActionDispatch::IntegrationTest
  PROCESSES_HREF = "/processes"

  setup do
    @organization = FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")
    host! @organization.host
    stub_webpack_manifest
    Decidim::ContentBlock.create!(
      organization: @organization, scope_name: "homepage", manifest_name: "hero", weight: 1, published_at: Time.current,
      settings: { "welcome_text_sk" => "Vitajte", "cta_button_path_sk" => "/contracts", "cta_button_text_sk" => "Prezrieť zmluvy" }
    )
  end

  teardown { unstub_webpack_manifest }

  test "contracts-only town keeps the header and hero as they were" do
    get "/"

    assert_response :ok
    assert_select "nav.main-bar__links-desktop a[href=?]", PROCESSES_HREF, count: 0
    assert_select "#hero-cta[href=?]", "/contracts"
    assert_select "#hero-cta-processes", count: 0
  end

  test "unpublished and private processes do not count" do
    FactoryBot.create(:participatory_process, :unpublished, organization: @organization)
    FactoryBot.create(:participatory_process, :published, :private, organization: @organization)

    get "/"

    assert_select "nav.main-bar__links-desktop a[href=?]", PROCESSES_HREF, count: 0
    assert_select "#hero-cta-processes", count: 0
  end

  test "another organization's published process does not count" do
    FactoryBot.create(:participatory_process, :published)

    get "/"

    assert_select "nav.main-bar__links-desktop a[href=?]", PROCESSES_HREF, count: 0
  end

  test "a published process adds the header link and the second hero CTA" do
    FactoryBot.create(:participatory_process, :published, organization: @organization)

    get "/"

    assert_select "nav.main-bar__links-desktop a[href=?]", PROCESSES_HREF, text: "Participácia"
    assert_select "#hero-cta[href=?]", "/contracts", text: /Prezrieť zmluvy/
    assert_select "#hero-cta[title=?]", "Prezrieť verejné zmluvy"
    assert_select "#hero-cta-processes[href=?]", PROCESSES_HREF, text: /Participácia/

    get "/?locale=en"
    assert_select "nav.main-bar__links-desktop a[href=?]", PROCESSES_HREF, text: "Participation"
    assert_select "#hero-cta[title=?]", "Browse public contracts"
  end

  test "the link leads to a page that renders" do
    FactoryBot.create(:participatory_process, :published, organization: @organization)

    get PROCESSES_HREF

    assert_response :ok
  end

  test "the answer is memoized in the request env" do
    FactoryBot.create(:participatory_process, :published, organization: @organization)
    env = {}

    assert ParticipationNavigation.processes?(@organization, nil, env)
    queries = count_queries { 2.times { ParticipationNavigation.processes?(@organization, nil, env) } }

    assert_equal 0, queries
  end

  test "the rake task adds the highlighted-processes block below the hero, once" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("civora:home:participation")
    task = Rake::Task["civora:home:participation"]
    blocks = -> { Decidim::ContentBlock.where(organization: @organization, scope_name: "homepage", manifest_name: "highlighted_processes") }

    out, = capture_io { task.invoke(@organization.id.to_s) }
    assert_match(/created/, out)
    assert_equal 1, blocks.call.count
    block = blocks.call.first
    assert_predicate block, :published?
    assert_equal 2, block.weight
    assert_equal 6, block.settings.max_results

    block.update!(published_at: nil, weight: 9)
    task.reenable
    out, = capture_io { task.invoke(@organization.id.to_s) }
    assert_match(/already present/, out)
    assert_equal 1, blocks.call.count
    assert_nil block.reload.published_at
    assert_equal 9, block.weight
  end

  test "the rake task keeps a weightless hero above the new block" do
    hero = Decidim::ContentBlock.find_by(organization: @organization, scope_name: "homepage", manifest_name: "hero")
    hero ||= Decidim::ContentBlock.create!(organization: @organization, scope_name: "homepage", manifest_name: "hero", published_at: Time.current)
    hero.update!(weight: nil)
    Rails.application.load_tasks unless Rake::Task.task_defined?("civora:home:participation")
    task = Rake::Task["civora:home:participation"]
    task.reenable
    capture_io { task.invoke(@organization.id.to_s) }

    order = Decidim::ContentBlock.where(organization: @organization, scope_name: "homepage").order(:weight).pluck(:manifest_name)
    assert_operator order.index("hero"), :<, order.index("highlighted_processes")
    assert_not_nil hero.reload.weight
  end

  test "the block renders on the homepage for a highlighted active process" do
    CivoraHome::ParticipationBlocks.call(@organization)
    process = FactoryBot.create(:participatory_process, :published, :promoted, organization: @organization,
                                                                               start_date: 1.week.ago, end_date: 1.month.from_now)

    get "/"

    assert_response :ok
    assert_select "#highlighted-processes"
    assert_select "#highlighted-processes a[href*=?]", process.slug
  end

  private

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w(SCHEMA TRANSACTION).include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    count
  end

  # CI compiles no webpack bundle (see AccessibilityFooterLinkTest).
  def stub_webpack_manifest
    @stubbed_manifest = Shakapacker.manifest
    @stubbed_names = [:lookup, :lookup!, :lookup_pack_with_chunks, :lookup_pack_with_chunks!]
    @stubbed_names.each do |name|
      chunks = name.to_s.include?("chunks")
      @stubbed_manifest.define_singleton_method(name) { |*_args, **_opts| chunks ? ["/packs-test/stub.js"] : "/packs-test/stub" }
    end
  end

  def unstub_webpack_manifest
    @stubbed_names&.each { |name| @stubbed_manifest.singleton_class.send(:remove_method, name) }
  end
end
