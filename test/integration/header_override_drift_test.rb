# frozen_string_literal: true

require "test_helper"

# The desktop header override is the gem partial plus one marked block. A
# Decidim bump that restructures the gem partial (0.32 did) would otherwise
# keep serving the stale copy silently; this fails until the file is re-based.
# Also covers the topbar search and the hero CTA cell, which are small edits of the gem files.
class HeaderOverrideDriftTest < ActiveSupport::TestCase
  PATH = "app/views/layouts/decidim/header/_main_links_desktop.html.erb"

  test "the header links override still matches decidim-core apart from the Civora block" do
    spec = Gem::Specification.find_by_name("decidim-core")
    gem_lines = File.read(File.join(spec.full_gem_path, PATH)).lines
    host_lines = Rails.root.join(PATH).read.lines
    host_lines.shift(host_lines.index { |line| line.include?("%>") } + 1) # the header comment

    body = without_civora_blocks(host_lines)

    assert_equal gem_lines, body, "#{PATH} drifted from decidim-core #{spec.version}: re-copy it and re-insert the Civora block"
  end

  test "the language chooser override is the gem partial plus the marked Civora block" do
    path = "app/views/layouts/decidim/header/_main_language_chooser.html.erb"
    spec = Gem::Specification.find_by_name("decidim-core")
    gem_lines = File.read(File.join(spec.full_gem_path, path)).lines
    host_lines = Rails.root.join(path).read.lines
    host_lines.shift(host_lines.index { |line| line.include?("%>") } + 1) # the header comment

    body = without_civora_blocks(host_lines)
    # The block replaces the gem's single locale-name line; the name stays in it.
    gem_name = gem_lines.index { |line| line.include?('t("name", scope: "locale"') }
    assert gem_name, "#{path} changed upstream: re-base it"
    assert_equal gem_lines.reject.with_index { |_, i| i == gem_name }, body, "#{path} drifted from decidim-core #{spec.version}: re-copy it and re-insert the Civora block"
    assert_includes Rails.root.join(path).read, 't("name", scope: "locale" )'
  end

  test "the topbar search override is the gem partial with only the catalogue substitutions" do
    path = "app/views/layouts/decidim/header/_main_search.html.erb"
    spec = Gem::Specification.find_by_name("decidim-core")
    expected = File.read(File.join(spec.full_gem_path, path))
    {
      "form_tag(decidim.search_path," => "form_tag(decidim_contracts_sk.contracts_path,",
      "    :term,\n" => "    :q,\n",
      "value: params[:term] || params.dig(:filter, :term)," => "value: params[:q],"
    }.each do |from, to|
      assert_includes expected, from, "#{path} changed upstream: re-base it"
      expected = expected.sub(from, to)
    end
    %w(placeholder title aria-label).each do |attribute|
      from = %(    #{attribute.include?("-") ? %("#{attribute}") : attribute}: t("decidim.search.term_input_placeholder"))
      expected = expected.sub(from, from.sub("decidim.search.term_input_placeholder", "decidim.contracts_sk.contracts.index.search_label")) if expected.include?(from)
    end
    expected = expected.sub('"aria-label": t("decidim.search.term_input_placeholder")', '"aria-label": t("decidim.contracts_sk.contracts.index.search_label")')
    host = Rails.root.join(path).read
    host = host.lines.drop(host.lines.index { |line| line.include?("%>") } + 1).join

    assert_equal expected, host, "#{path} drifted from decidim-core #{spec.version}: re-base it"
  end

  test "the hero CTA cell keeps the gem's button verbatim" do
    path = "app/cells/decidim/content_blocks/hero/cta_button.erb"
    spec = Gem::Specification.find_by_name("decidim-core")
    gem_lines = File.read(File.join(spec.full_gem_path, path)).lines.map(&:strip).reject(&:empty?)
    host_lines = Rails.root.join(path).read.lines.map(&:strip)

    gem_lines.each { |line| assert_includes host_lines, line, "#{path} drifted from decidim-core #{spec.version}: missing #{line.inspect}" }
  end

  private

  # The host copy minus every Civora: start .. Civora: end block (a block may
  # open or close a Ruby conditional, so there can be several).
  def without_civora_blocks(lines)
    assert_equal lines.count { |line| line.include?("Civora: start") }, lines.count { |line| line.include?("Civora: end") }, "unbalanced Civora block markers"
    inside = false
    lines.reject do |line|
      inside = true if line.include?("<%# Civora: start %>")
      skip = inside
      inside = false if line.include?("<%# Civora: end %>")
      skip
    end
  end
end
