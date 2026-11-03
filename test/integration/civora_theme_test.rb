# frozen_string_literal: true

require "test_helper"
require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"

# The Civora public theme (docs/appearance.md): the footer signature renders on
# a public page, the typefaces come from local files, and the colour tokens
# keep WCAG AA contrast with the towns' palettes. The CSS itself is checked in
# the browser (see the PR); these are the parts that can break silently.
class CivoraThemeTest < ActionDispatch::IntegrationTest
  STYLES = Rails.root.join("app/packs/stylesheets/decidim")
  FONT_DIR = Rails.root.join("app/packs/fonts/civora")

  # Palettes a town may reasonably choose: the demo towns (Považská Bystrica and
  # Vranov nad Topľou share docs/appearance.md's blue), that palette's other
  # two colours, Dvere indigo (the fallback), and a light primary (yellow) as a
  # stress case for the footer band.
  PRIMARIES = %w(#00539B #1F6FC0 #C8102E #34408A #2E7D32 #FFD700).freeze

  setup do
    @organization = FactoryBot.create(:organization, available_locales: %w(sk en), default_locale: "sk")
    host! @organization.host
    stub_webpack_manifest
  end

  teardown { unstub_webpack_manifest }

  test "the footer carries the Civora signature on a public page" do
    get "/sk/"

    assert_response :ok
    assert_select "footer .mini-footer a.civora-sign__link[href=?]", "https://civora.sk" do
      assert_select "span", text: "Civora"
      assert_select "svg[aria-hidden=true]"
    end
    # Decidim's own credit stays: the signature does not replace it.
    assert_select "footer .mini-footer a[href=?]", "https://decidim.org/"
  end

  test "the signature sits in the footer only once per page" do
    get "/sk/"

    assert_select "a.civora-sign__link", count: 1
  end

  test "every font file is declared from a local path and exists" do
    css = STYLES.join("civora/_fonts.scss").read
    sources = css.scan(/url\("([^"]+)"\)/).flatten

    assert_equal 8, sources.size, "Alegreya Sans 700 (2 subsets) and Source Sans 3 400/600/700 (2 subsets each)"
    sources.each do |source|
      assert_match %r{\Afonts/civora/[a-z0-9-]+\.woff2\z}, source
      assert FONT_DIR.join(File.basename(source)).file?, "#{source} is not in app/packs/fonts/civora"
    end
    assert_equal sources.sort, Dir[FONT_DIR.join("*.woff2")].map { |path| "fonts/civora/#{File.basename(path)}" }.sort,
                 "a font file is shipped but not declared, or declared but not shipped"
  end

  test "the stylesheets and the tailwind template load nothing from a third-party host" do
    files = Dir[STYLES.join("**/*.scss")] + [Rails.root.join("config/tailwind.config.js.erb").to_s]
    files.each do |path|
      source = File.read(path)
      assert_no_match(/fonts\.(googleapis|gstatic)\.com/, source, "#{path} uses Google Fonts")
      assert_no_match(%r{url\(\s*["']?https?://}, source, "#{path} loads a remote url()")
      assert_no_match(/@import\s+url\(/, source, "#{path} @imports a remote stylesheet")
    end
  end

  test "the font families are declared, wired to the tailwind font utilities and named by the foundation" do
    template = Rails.root.join("config/tailwind.config.js.erb").read
    css = STYLES.join("civora/_fonts.scss").read

    foundation = STYLES.join("civora/_foundation.scss").read
    { "Source Sans 3" => "--civora-font-sans", "Alegreya Sans" => "--civora-font-display" }.each do |family, variable|
      assert_includes foundation, %(#{variable}: "#{family}"), "#{variable} does not start with #{family}"
      assert_includes css, %(font-family: "#{family}")
    end
    assert_includes template, "var(--civora-font-sans,"
    assert_includes template, "var(--civora-font-display,"
  end

  test "the font licence ships with the font files" do
    assert FONT_DIR.join("OFL.txt").read.include?("SIL OPEN FONT LICENSE Version 1.1")
  end

  test "ink and muted text keep AA contrast on paper, paper-light and cream" do
    tokens = css_tokens
    %w(ink muted).each do |text|
      %w(paper paper-light cream).each do |ground|
        assert_operator contrast(tokens[text], tokens[ground]), :>=, 4.5, "#{text} on #{ground}"
      end
    end
  end

  test "tailwind neutrals used for text keep AA contrast on the Civora grounds" do
    tokens = css_tokens
    # --civora-*-rgb triplets: black (ink), gray (muted), gray-2 (secondary ink).
    texts = %w(black gray gray-2).index_with { |name| triplet_hex(tokens.fetch("#{name}-rgb")) }

    texts.each do |name, hex|
      %w(paper paper-light cream).each { |ground| assert_operator contrast(hex, tokens[ground]), :>=, 4.5, "#{name} (#{hex}) on #{ground}" }
    end
  end

  test "the neutral triplets agree with the named tokens" do
    tokens = css_tokens

    assert_equal tokens["ink"], triplet_hex(tokens["black-rgb"])
    assert_equal tokens["muted"], triplet_hex(tokens["gray-rgb"])
    assert_equal tokens["cream"], triplet_hex(tokens["gray-5-rgb"])
    assert_equal tokens["cream"], triplet_hex(tokens["background-rgb"])
    assert_equal tokens["paper-light"], triplet_hex(tokens["background-2-rgb"])
    assert_equal tokens["rule"], triplet_hex(tokens["gray-3-rgb"])
  end

  test "the tailwind template falls back to Decidim's own value, so the admin is unchanged" do
    template = Rails.root.join("config/tailwind.config.js.erb").read
    decidim_triplets = {
      "black" => "2 2 3", "gray" => "107 114 128", "gray-2" => "62 76 92", "gray-3" => "225 229 239",
      "gray-5" => "246 248 250", "gray-6" => "211 213 217", "background" => "243 244 247",
      "background-2" => "250 251 252", "background-3" => "239 239 239", "background-4" => "228 238 255",
      "background-5" => "233 233 233"
    }

    decidim_triplets.each do |name, triplet|
      assert_match(%r{(civora\("--civora-#{name}-rgb", "#{triplet}"\)|rgb\(var\(--civora-#{name}-rgb, #{triplet}\) / 0\.[68]\))}, template,
                   "the #{name} fallback is not Decidim's value")
    end
    assert_includes template, "var(--civora-radius, 0.25rem)"
    assert_includes template, 'var(--civora-font-sans, "Source Sans Pro")'
  end

  test "the Civora variables are defined in the public pack only, never in an admin pack" do
    Dir[Rails.root.join("app/packs/**/*admin*").to_s].select { |path| File.file?(path) }.each do |path|
      assert_not_includes File.read(path), "--civora-", "#{path} must not carry the Civora theme"
    end
    assert STYLES.join("decidim_application.scss").read.include?('@use "civora/foundation";')
  end

  test "an input edge reaches 3:1 on its ground" do
    tokens = css_tokens
    %w(paper paper-light).each do |ground|
      assert_operator contrast(tokens["edge"], tokens[ground]), :>=, 3.0, "edge on #{ground}"
    end
  end

  test "paper text on the footer band stays AA for every town palette" do
    tokens = css_tokens
    PRIMARIES.each do |primary|
      band = band_for(primary)
      assert_operator contrast(tokens["paper"], band), :>=, 4.5, "paper text on the band of #{primary} (#{band})"
    end
  end

  test "the band formula in the stylesheet is the one the test models" do
    assert_includes STYLES.join("civora/_foundation.scss").read, "--civora-band: color-mix(in srgb, var(--primary, #34408a) 32%, #151428);"
  end

  private

  # --civora-NAME: #rrggbb; and --civora-NAME-rgb: r g b; declarations of the foundation stylesheet.
  def css_tokens
    @css_tokens ||= begin
      source = STYLES.join("civora/_foundation.scss").read
      source.scan(/--civora-([a-z0-9-]+):\s*(#\h{6});/).to_h.merge(source.scan(/--civora-([a-z0-9-]+-rgb):\s*(\d+ \d+ \d+);/).to_h)
    end
  end

  def triplet_hex(triplet)
    format("#%02x%02x%02x", *triplet.split.map(&:to_i))
  end

  # color-mix(in srgb, <primary> 32%, #151428): a per-channel mix in sRGB.
  def band_for(primary)
    base = rgb("#151428")
    mixed = rgb(primary).zip(base).map { |p, b| ((p * 0.32) + (b * 0.68)).round }
    format("#%02x%02x%02x", *mixed)
  end

  def rgb(hex)
    hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
  end

  def luminance(hex)
    r, g, b = rgb(hex).map do |channel|
      c = channel / 255.0
      c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
    end
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def contrast(one, other)
    light, dark = [luminance(one), luminance(other)].sort.reverse
    (light + 0.05) / (dark + 0.05)
  end

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
