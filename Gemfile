# frozen_string_literal: true

source "https://rubygems.org"

ruby RUBY_VERSION

gem "decidim", "0.32.1"
# gem "decidim-ai", "0.32.1"
# gem "decidim-collaborative_texts", "0.32.1"
# gem "decidim-conferences", "0.32.1"
# gem "decidim-demographics", "0.32.1"
# gem "decidim-design", "0.32.1"
# gem "decidim-elections", "0.32.1"
# gem "decidim-initiatives", "0.32.1"
# gem "decidim-templates", "0.32.1"

gem "decidim-contracts_sk", github: "civora-org/decidim-contracts_sk", tag: "v1.8.1"

gem "bootsnap", "~> 1.3"

# Decidim 0.32 eager-loads its seed classes (decidim-comments app/models/.../seed.rb),
# which require faker even in production. Before 0.32 only decidim-dev pulled it.
gem "faker", "~> 3.2"

# selma 0.5.3 was published as source only (needs a Rust toolchain at install);
# 0.5.2 ships precompiled gems for the Linux and macOS platforms in the lockfile.
# Pulled in by decidim-core through html-pipeline. Lift the cap once a
# precompiled release exists again.
gem "selma", "< 0.5.3"

gem "puma", ">= 6.3.1"

# TOTP primitives for the admin second factor (civora-org/civora-platform#164, ADR-010)
gem "rotp", "~> 6.3"

# Observability baseline (civora-org/civora-platform#51)
gem "prometheus_exporter", "~> 2.1"
gem "sentry-rails", "~> 5.22"
gem "sentry-ruby", "~> 5.22"

group :development, :test do
  gem "byebug", "~> 11.0", platform: :mri

  gem "brakeman", "~> 7.0"
  gem "bundler-audit", "~> 0.9"
  gem "decidim-dev", "0.32.1"
  # Rails 8.1 resolves minitest 6, which moved minitest/mock into its own gem
  # and is not yet what Rails' test runner is built for; stay on 5.x.
  gem "minitest", "~> 5.27"
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
