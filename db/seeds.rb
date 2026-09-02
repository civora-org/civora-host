# frozen_string_literal: true

# Idempotent, deterministic seeds — no faker, no PII (see civora-org/civora-platform#48).
#
# Decidim cannot serve any page (including the /contracts engine mount)
# without a current organization, so a minimal one is required on a fresh
# database. Keep this seed minimal and safe to run in production.

Decidim::Organization.find_or_create_by!(host: ENV.fetch("DECIDIM_ORG_HOST", "localhost")) do |org|
  org.name = { "en" => "Civora", "sk" => "Civora" }
  org.default_locale = "en"
  org.available_locales = %w(en sk)
  org.reference_prefix = "CIV"
  org.time_zone = "Bratislava"
end
