# frozen_string_literal: true

# See app/lib/sk_translation_spacing.rb. Runs after all locale files (gems and
# config/locales) are loaded, and again whenever I18n reloads in development.
Rails.application.config.after_initialize do
  SkTranslationSpacing.apply!
  ActiveSupport::Reloader.to_prepare { SkTranslationSpacing.apply! } if Rails.env.development?
end
