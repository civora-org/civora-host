# frozen_string_literal: true

require "test_helper"

class SkTranslationSpacingTest < ActiveSupport::TestCase
  test "no Slovak string glues a word to an interpolation" do
    glued = []
    walk = lambda do |node, path|
      case node
      when Hash then node.each { |key, value| walk.call(value, path + [key]) }
      when String then glued << path.join(".") if node.match?(SkTranslationSpacing::GLUED)
      end
    end
    walk.call(I18n.backend.send(:translations)[:sk], [])

    assert_empty glued, "glued interpolations left in :sk: #{glued.first(10).join(", ")}"
  end

  test "the sign-in failure reads as a sentence" do
    assert_equal "Nesprávna e-mailová adresa alebo heslo.",
                 I18n.t("devise.failure.invalid", locale: :sk, authentication_keys: "E-mailová adresa")
  end

  test "a core string with a glued interpolation gets its space back" do
    assert_equal "Krok 2 z 5",
                 I18n.t("decidim.wizard_step_form.wizard_header.step_of", locale: :sk, current_step: 2, total_steps: 5)
  end

  test "fix leaves URLs, spaced and leading interpolations alone" do
    assert_equal "Vitajte na %{organization}", SkTranslationSpacing.fix("Vitajte na%{organization}")
    assert_equal "%{user_name} vytvoril", SkTranslationSpacing.fix("%{user_name} vytvoril")
    assert_equal "(%{count})", SkTranslationSpacing.fix("(%{count})")
    assert_equal "https://x.sk/%{slug}", SkTranslationSpacing.fix("https://x.sk/%{slug}")
  end
end
