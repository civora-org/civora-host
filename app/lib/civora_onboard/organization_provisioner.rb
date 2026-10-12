# frozen_string_literal: true

module CivoraOnboard
  # Creates (or converges) one municipality's Decidim organization and its
  # first admin. Idempotent: the organization is found by host; a second run
  # changes nothing unless the config changed.
  #
  # A new organization goes through Decidim's own system command
  # (Decidim::System::CreateOrganization), so the default pages, help pages
  # and homepage content blocks are created exactly as the system dashboard
  # would, and the first admin is invited by it. The command only knows the
  # default-locale name, so the remaining settings (all-locale names, time
  # zone, ...) are applied afterwards by #converge.
  #
  # The admin password comes from the caller (ENV in the rake task), is only
  # applied to an admin who has not set one yet, and is never logged.
  class OrganizationProvisioner
    Result = Struct.new(:organization, :created, :changes, :admin_status, keyword_init: true)

    def self.call(config, admin_password: nil, dry_run: false)
      new(config, admin_password:, dry_run:).call
    end

    def initialize(config, admin_password:, dry_run:)
      @config = config
      @admin_password = admin_password.to_s
      @dry_run = dry_run
    end

    def call
      organization = Decidim::Organization.find_by(host: @config.host)
      return dry_result(organization) if @dry_run

      created = organization.nil?
      organization = create_organization! if created
      changes = converge(organization)
      Result.new(organization:, created:, changes:,
                 admin_status: ensure_admin(organization))
    end

    private

    def dry_result(organization)
      changes = organization ? pending_changes(organization).keys : []
      Result.new(organization:, created: false, changes:,
                 admin_status: organization ? admin_state(organization) : :would_invite)
    end

    def create_organization!
      form = Decidim::System::RegisterOrganizationForm.from_params(
        name: @config.name[@config.default_locale] || @config.name.values.first,
        short_name: @config.short_name,
        host: @config.host,
        secondary_hosts: @config.secondary_hosts.join("\n"),
        reference_prefix: @config.reference_prefix,
        default_locale: @config.default_locale,
        available_locales: @config.available_locales,
        users_registration_mode: @config.users_registration_mode,
        organization_admin_email: @config.admin_email,
        organization_admin_name: @config.admin_name,
        file_upload_settings: {}
      ).with_context(current_user: nil)

      created = nil
      host = @config.host # command callbacks run with the listener as self
      Decidim::System::CreateOrganization.call(form) do
        on(:ok) { created = Decidim::Organization.find_by!(host:) }
        on(:invalid) { raise "Decidim refused the organization: #{form.errors.full_messages.to_sentence}" }
        on(:invalid_invitation) { raise "Decidim could not invite the first admin (check admin_email)" }
      end
      created
    end

    def desired_attributes
      {
        name: @config.localized_name,
        short_name: @config.localized_name.transform_values { @config.short_name },
        default_locale: @config.default_locale,
        available_locales: @config.available_locales,
        time_zone: @config.time_zone,
        reference_prefix: @config.reference_prefix,
        secondary_hosts: @config.secondary_hosts,
        users_registration_mode: @config.users_registration_mode
      }
    end

    def pending_changes(organization)
      desired_attributes.reject do |attribute, value|
        current = organization.public_send(attribute)
        # short_name is only required in the default locale; keep other
        # locales as they are so an admin's edits survive a re-run.
        current = current.to_h.slice(*value.keys) if value.is_a?(Hash) && current.respond_to?(:slice)
        current == value
      end
    end

    def converge(organization)
      changes = pending_changes(organization)
      organization.update!(changes) if changes.any?
      changes.keys
    end

    def admin_scope(organization)
      Decidim::User.where(organization:)
    end

    def admin_state(organization)
      user = admin_scope(organization).find_by(email: @config.admin_email)
      return :would_invite unless user

      activated?(user) && user.admin? ? :ready : :invited
    end

    # Returns :ready (can sign in as admin), :invited (invitation mail sent,
    # no password configured) or :password_set.
    def ensure_admin(organization)
      user = admin_scope(organization).find_by(email: @config.admin_email)
      user ||= invite_admin(organization)

      user.admin = true
      return finalize_invitation(organization, user) if @admin_password.present? && !activated?(user)

      user.save! if user.changed?
      activated?(user) ? :ready : :invited
    end

    def activated?(user)
      user.encrypted_password.present? && user.confirmed_at.present? && user.admin_terms_accepted_at.present?
    end

    def finalize_invitation(organization, user)
      user.password = @admin_password
      user.password_confirmation = @admin_password
      user.tos_agreement = "1"
      user.accepted_tos_version = organization.tos_version
      user.admin_terms_accepted_at ||= Time.current
      user.confirmed_at ||= Time.current
      user.invitation_accepted_at ||= Time.current
      user.invitation_token = nil # a pending token blocks password sign-in (devise_invitable)
      user.locale = @config.default_locale
      user.save!
      :password_set
    end

    def invite_admin(organization)
      form = Decidim::InviteUserForm.from_params(
        name: @config.admin_name, email: @config.admin_email, role: "admin",
        invitation_instructions: "organization_admin_invitation_instructions"
      ).with_context(current_user: nil, current_organization: organization)
      Decidim::InviteUser.call(form)
      admin_scope(organization).find_by!(email: @config.admin_email)
    end
  end
end
