# frozen_string_literal: true

require "test_helper"
require "support/participation_link_helpers"

# civora-org/civora-platform#131 (host part): the two Decidim view overrides
# render the engine's related-contracts block on a result page and a budgets
# project page, and nothing when no published contract of the organization is
# linked.
class RelatedContractsViewsTest < ActionDispatch::IntegrationTest
  include ParticipationLinkHelpers

  OVERRIDES = {
    "decidim-accountability" => "app/views/decidim/accountability/results/_project.html.erb",
    "decidim-budgets" => "app/views/decidim/budgets/projects/show.html.erb"
  }.freeze

  setup do
    @tenant = build_tenant
    @organization = @tenant[:organization]
    @result = create_result(@tenant)
    @project = create_project(@tenant)
    host! @organization.host
    stub_webpack_manifest
  end

  teardown { unstub_webpack_manifest }

  test "result page lists a published linked contract" do
    contract = create_contract(@tenant, title: "Detske ihrisko - dodavka")
    link!(contract, @result)

    get result_path(@result)

    assert_response :ok
    assert_select "section.cs-related" do
      assert_select "a.cs-related__title[href=?]", "/contracts/#{contract.id}", text: "Detske ihrisko - dodavka"
    end
  end

  test "project page lists a published linked contract" do
    contract = create_contract(@tenant, title: "Zostava preliezok")
    link!(contract, @project)

    get project_path(@project)

    assert_response :ok
    assert_select "section.cs-related a.cs-related__title[href=?]", "/contracts/#{contract.id}", text: "Zostava preliezok"
  end

  test "result page renders nothing without a link" do
    get result_path(@result)

    assert_response :ok
    assert_select ".cs-related", count: 0
    assert_no_match(/cs-related/, response.body)
  end

  test "project page renders nothing without a link" do
    get project_path(@project)

    assert_response :ok
    assert_no_match(/cs-related/, response.body)
  end

  test "non-published contracts are not shown" do
    %w(draft in_review archived).each do |state|
      link!(create_contract(@tenant, state: state), @result)
    end

    get result_path(@result)

    assert_response :ok
    assert_no_match(/cs-related/, response.body)
  end

  test "a published contract of another organization linked to the same id is not shown" do
    other = build_tenant
    foreign = create_contract(other, title: "Cudzia zmluva")
    link!(foreign, @result)

    get result_path(@result)

    assert_response :ok
    assert_no_match(/cs-related|Cudzia zmluva/, response.body)
  end

  test "the overrides still match the installed Decidim gems apart from the Civora additions" do
    OVERRIDES.each do |gem_name, path|
      gem_dir = Gem::Specification.find_by_name(gem_name).full_gem_path
      gem_lines = File.read(File.join(gem_dir, path)).lines
      host_lines = Rails.root.join(path).read.lines
      host_lines.shift(host_lines.index { |line| line.include?("%>") } + 1) # the header comment
      body = host_lines.reject { |line| line.include?("<%# Civora %>") }

      assert_equal gem_lines, body, "#{path} drifted from #{gem_name} #{Gem::Specification.find_by_name(gem_name).version}: re-copy it and re-apply the Civora line"
      assert_equal(1, host_lines.count { |line| line.include?("<%# Civora %>") })
    end
  end

  private

  # CI compiles no webpack bundle, so asset lookups (icons, packs) would raise
  # on the empty manifest. The views under test do not depend on asset
  # contents, only on the lookups not raising.
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

  def result_path(result)
    Decidim::ResourceLocatorPresenter.new(result).path
  end

  def project_path(project)
    Decidim::ResourceLocatorPresenter.new([project.budget, project]).path
  end
end
