# frozen_string_literal: true

require_relative "boot"

# Slovak first. Decidim reads these from the environment when decidim-core
# loads (Decidim.default_locale / Decidim.available_locales, which feed
# I18n.default_locale and the locale route scope), so they must be set before
# `require "decidim/rails"`. Without them the global default is "en" and
# Decidim::LocaleRouterDetector (decidim-core 0.32.2,
# lib/decidim/routes/locale_redirects.rb) sends an anonymous visitor of "/" to
# "/en/" before it consults the organization's default_locale. An operator can
# still override either variable in the environment.
ENV["DECIDIM_DEFAULT_LOCALE"] = "sk" if ENV["DECIDIM_DEFAULT_LOCALE"].to_s.empty?
ENV["DECIDIM_AVAILABLE_LOCALES"] = "sk,en" if ENV["DECIDIM_AVAILABLE_LOCALES"].to_s.empty?

require "decidim/rails"

# Add the frameworks used by your app that are not loaded by Decidim.
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DecidimApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
