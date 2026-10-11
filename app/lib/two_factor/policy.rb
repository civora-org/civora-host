# frozen_string_literal: true

module TwoFactor
  # Who must hold and use a second factor, and whether this session did.
  #
  # Required: organization admins (admin: true) and holders of an engine
  # (decidim-contracts_sk) role, resolved through the engine's own
  # role_resolver so a host override is honoured. Public participants, and
  # Decidim::System::Admin (a separate model with its own sign-in), are out of
  # scope (civora-org/civora-platform#164).
  module Policy
    SESSION_KEY = :two_factor_verified_user_id

    module_function

    def required?(user)
      return false if user.blank? || user.deleted?

      user.admin? || engine_role_holder?(user)
    end

    def engine_role_holder?(user)
      return false unless defined?(Decidim::ContractsSk) && Decidim::ContractsSk.role_resolver

      Array(Decidim::ContractsSk.role_resolver.call(user, {})).any?
    end

    def credential_for(user)
      TwoFactor::Credential.confirmed.find_by(decidim_user_id: user.id)
    end

    def enrolled?(user)
      credential_for(user).present?
    end

    def verified?(session, user)
      user.present? && session[SESSION_KEY] == user.id
    end

    def mark_verified!(session, user)
      session[SESSION_KEY] = user.id
    end

    def clear!(session)
      session.delete(SESSION_KEY)
    end

    # The seam the engine admin consults (Decidim::ContractsSk.second_factor_satisfied).
    # Also true for users who are not required to use a second factor.
    def satisfied?(user, session)
      !required?(user) || (enrolled?(user) && verified?(session, user))
    end
  end
end
