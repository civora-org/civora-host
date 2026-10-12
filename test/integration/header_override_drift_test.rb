# frozen_string_literal: true

require "test_helper"

# The desktop header override is the gem partial plus one marked block. A
# Decidim bump that restructures the gem partial (0.32 did) would otherwise
# keep serving the stale copy silently; this fails until the file is re-based.
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
end
