# frozen_string_literal: true

# Decidim's Slovak translations lose the space before an interpolation in
# dozens of strings ("Neplatný%{authentication_keys}", "Krok%{current_step}
# z%{total_steps}", "Dobrý deň%{recipient}"), which renders words glued
# together ("NeplatnýE-mailová adresa", "Krok1 z5"). Rather than overriding
# each key (and missing the ones the next Decidim release adds), this puts the
# space back wherever a letter is directly followed by "%{" in the :sk store.
# Run once after the translations load (config/initializers/sk_translation_spacing.rb).
module SkTranslationSpacing
  GLUED = /(\p{L})%\{/

  module_function

  def apply!(backend = I18n.backend)
    return 0 unless backend.respond_to?(:store_translations, true)

    backend.send(:init_translations) if backend.respond_to?(:initialized?) && !backend.initialized?
    store = backend.send(:translations)[:sk]
    return 0 unless store

    fixed = {}
    count = collect(store, [], fixed)
    fixed.each { |path, value| backend.store_translations(:sk, nest(path, value)) }
    count
  end

  def fix(text) = text.gsub(GLUED, '\1 %{')

  def collect(node, path, fixed)
    case node
    when Hash then node.sum { |key, value| collect(value, path + [key], fixed) }
    when String
      return 0 unless node.match?(GLUED)

      fixed[path] = fix(node)
      1
    else 0
    end
  end

  def nest(path, value) = path.reverse.reduce(value) { |acc, key| { key => acc } }
end
