# frozen_string_literal: true

source "https://rubygems.org"

ruby RUBY_VERSION

gem "decidim", "0.31.7"
# gem "decidim-ai", "0.31.7"
# gem "decidim-collaborative_texts", "0.31.7"
# gem "decidim-conferences", "0.31.7"
# gem "decidim-demographics", "0.31.7"
# gem "decidim-design", "0.31.7"
# gem "decidim-elections", "0.31.7"
# gem "decidim-initiatives", "0.31.7"
# gem "decidim-templates", "0.31.7"

gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.5.0"

gem "bootsnap", "~> 1.3"

gem "puma", ">= 6.3.1"

# Observability baseline (civora-org/civora-platform#51)
gem "prometheus_exporter", "~> 2.1"
gem "sentry-rails", "~> 5.22"
gem "sentry-ruby", "~> 5.22"

group :development, :test do
  gem "byebug", "~> 11.0", platform: :mri

  gem "brakeman", "~> 7.0"
  gem "bundler-audit", "~> 0.9"
  gem "decidim-dev", "0.31.7"
  # rubocop-rake: required by the inherited decidim-dev rubocop config
  gem "net-imap", "~> 0.5.0"
  gem "net-pop", "~> 0.1.1"
  gem "rubocop-rake", "~> 0.7"
end

group :development do
  gem "letter_opener_web", "~> 2.0"
  gem "listen", "~> 3.1"
  gem "web-console", "~> 4.2"
end
