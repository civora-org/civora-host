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

    start = host_lines.index { |line| line.include?("<%# Civora: start %>") }
    finish = host_lines.index { |line| line.include?("<%# Civora: end %>") }
    assert start && finish && start < finish, "the Civora block markers are missing"

    body = host_lines[0...start] + host_lines[(finish + 1)..]
    assert_equal gem_lines, body, "#{PATH} drifted from decidim-core #{spec.version}: re-copy it and re-insert the Civora block"
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
end
