# frozen_string_literal: true

module TwoFactor
  # Shared plumbing for the enrolment, challenge and recovery-code pages. They
  # render in Decidim's public layout (the user is signed in with a password but
  # not yet allowed into the admin), so they must NOT inherit
  # Decidim::Admin::ApplicationController, whose gate would redirect to itself.
  class BaseController < Decidim::ApplicationController
    include Decidim::FormFactory

    # These pages must not overwrite the return location the gate stored.
    skip_before_action :store_current_location

    before_action :authenticate_user!
    before_action :require_second_factor_user!

    helper_method :recovery_codes_remaining

    private

    # Participants never see these pages.
    def require_second_factor_user!
      redirect_to decidim.root_path unless TwoFactor::Policy.required?(current_user)
    end

    def code_form
      form(TwoFactor::CodeForm).from_params(params)
    end

    def empty_code_form
      form(TwoFactor::CodeForm).from_params({})
    end

    def after_second_factor_path
      stored_location_for(:user).presence ||
        (current_user.admin? ? decidim_admin.root_path : decidim_contracts_sk.admin_root_path)
    end

    def credential
      @credential ||= TwoFactor::Policy.credential_for(current_user)
    end

    def recovery_codes_remaining
      credential&.unused_recovery_codes_count.to_i
    end

    def verification_failed(form, result, view)
      if result == :locked
        flash.now[:alert] = t("two_factor.locked")
        render view, status: :too_many_requests
      else
        form.errors.add(:code, t("two_factor.invalid_code"))
        render view, status: :unprocessable_entity
      end
    end
  end
end
