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

# Homepage hero (idempotent): a welcome text and a CTA into the contracts
# catalogue — without it the Decidim homepage renders empty. Translated
# content-block settings persist under per-locale keys ("welcome_text_en").
org = Decidim::Organization.find_by(host: ENV.fetch("DECIDIM_ORG_HOST", "localhost"))
hero = Decidim::ContentBlock.find_or_initialize_by(
  organization: org, scope_name: "homepage", manifest_name: "hero"
)
hero.published_at ||= Time.current
hero.settings = (hero[:settings] || {}).merge(
  "welcome_text_en" => "Public contracts of Slovak municipalities — transparent, structured, searchable.",
  "welcome_text_sk" => "Verejné zmluvy slovenských obcí a miest — transparentné, štruktúrované, s vyhľadávaním.",
  "cta_button_path_en" => "/contracts",
  "cta_button_path_sk" => "/contracts",
  "cta_button_text_en" => "Browse contracts",
  "cta_button_text_sk" => "Prezrieť zmluvy"
)
hero.save!
