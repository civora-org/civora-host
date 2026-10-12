# frozen_string_literal: true

module CivoraOnboard
  # Post-onboarding checks for one organization (the runbook's verification
  # checklist, the parts a machine can answer). Read-only; counts and ids
  # only.
  class Verification
    Check = Struct.new(:label, :ok, :detail, keyword_init: true)

    def self.call(organization)
      new(organization).call
    end

    def initialize(organization)
      @organization = organization
    end

    def call
      [ico_check, ico_unique_check, locale_check, admin_check, scope_check, catalogue_check].compact
    end

    private

    attr_reader :organization

    def ico
      @ico ||= Decidim::ContractsSk.crz_organization_ico(organization)
    end

    def env_name
      "CRZ_ICO_ORG_#{organization.id}"
    end

    def ico_check
      return Check.new(label: "CRZ IČO configured", ok: false, detail: "#{env_name} is not set in this process") unless ico

      valid = Ico.checksum_valid?(ico)
      Check.new(label: "CRZ IČO configured", ok: valid, detail: valid ? "#{env_name} set (#{ico})" : "#{env_name}=#{ico} fails the IČO checksum")
    end

    # Two organizations sharing one IČO would mirror the same contracts.
    def ico_unique_check
      return unless ico

      clashes = Decidim::Organization.where.not(id: organization.id).select do |other|
        Decidim::ContractsSk.crz_organization_ico(other) == ico
      end
      Check.new(label: "IČO is unique to this organization", ok: clashes.empty?,
                detail: clashes.empty? ? "no other organization uses it" : "also used by organization ids #{clashes.map(&:id).join(", ")}")
    end

    def locale_check
      ok = organization.default_locale == "sk" && organization.time_zone == "Bratislava"
      Check.new(label: "Slovak defaults", ok:,
                detail: "default_locale=#{organization.default_locale} time_zone=#{organization.time_zone} available=#{organization.available_locales.join(",")}")
    end

    def admin_check
      admins = Decidim::User.where(organization:, admin: true)
      ready = admins.where.not(admin_terms_accepted_at: nil).where.not(encrypted_password: [nil, ""]).count
      Check.new(label: "An admin can sign in", ok: ready.positive?,
                detail: "#{admins.count} admin(s), #{ready} with password and accepted admin terms")
    end

    # The IČO isolation check: nothing mirrored that has the IČO on neither party.
    def scope_check
      return unless ico

      matched = Decidim::ContractsSk::CrzImport::Prune.call(organization:, ico:, confirm: false).matched
      Check.new(label: "Only this city's contracts are mirrored", ok: matched.zero?,
                detail: "#{matched} out-of-scope CRZ mirror(s) (prune_out_of_scope dry run)")
    end

    def catalogue_check
      scope = Decidim::ContractsSk::Contract.where(organization:)
      Check.new(label: "Catalogue", ok: true, detail: "#{scope.count} contract(s), #{scope.published.count} published")
    rescue ActiveRecord::StatementInvalid, NameError
      Check.new(label: "Catalogue", ok: false, detail: "could not count contracts")
    end
  end
end
