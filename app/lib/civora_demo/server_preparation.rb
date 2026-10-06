# frozen_string_literal: true

module CivoraDemo
  # Prepares one organization for the public demo server
  # (docs/ops/demo-server.md): Slovak default locale, a visible "DEMO" banner
  # on every page (Decidim's omnipresent banner, organization settings), and
  # one demo admin. Idempotent: re-running updates the same records.
  #
  # The banner is an organization setting, not a template override, so it
  # survives Decidim upgrades and stays out of the pilot stack: nothing calls
  # this class unless the demo server tooling does (the rake task additionally
  # needs DEMO_MODE=1).
  #
  # The admin password is only ever read from the caller's argument (the
  # environment in the rake task) and is never logged or returned.
  class ServerPreparation
    BANNER_TITLE = { "sk" => "DEMO — fiktívne údaje", "en" => "DEMO — fictional data" }.freeze
    BANNER_TEXT = {
      "sk" => "Ukážková inštancia. Nie sú tu žiadne skutočné zmluvy ani osobné údaje.",
      "en" => "Demonstration instance. It holds no real contracts or personal data."
    }.freeze

    def self.call(organization, admin_email:, admin_password:)
      new(organization, admin_email, admin_password).call
    end

    def initialize(organization, admin_email, admin_password)
      @organization = organization
      @admin_email = admin_email.to_s.strip.downcase
      @admin_password = admin_password.to_s
    end

    def call
      configure_organization
      ensure_admin if @admin_email.present?
      @organization
    end

    private

    def configure_organization
      @organization.update!(
        default_locale: "sk",
        available_locales: %w(sk en),
        enable_omnipresent_banner: true,
        omnipresent_banner_url: "/contracts",
        omnipresent_banner_title: BANNER_TITLE,
        omnipresent_banner_short_description: BANNER_TEXT
      )
    end

    def ensure_admin
      raise ArgumentError, "DEMO_ADMIN_PASSWORD is required to create the demo admin" if @admin_password.blank? && !admin_scope.exists?(email: @admin_email)

      user = admin_scope.find_or_initialize_by(email: @admin_email)
      if user.new_record?
        local = @admin_email.split("@").first
        user.name = "Demo admin"
        user.nickname = local.gsub(/[^a-z0-9_]/, "_").first(20)
        user.tos_agreement = "1"
        user.locale = "sk"
      end
      user.accepted_tos_version = @organization.tos_version
      user.admin = true
      user.admin_terms_accepted_at ||= Time.current
      user.confirmed_at ||= Time.current
      if @admin_password.present? && !user.valid_password?(@admin_password)
        user.password = @admin_password
        user.password_confirmation = @admin_password
      end
      user.save!
      user
    end

    def admin_scope
      Decidim::User.where(organization: @organization)
    end
  end
end
