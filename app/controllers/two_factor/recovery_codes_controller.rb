# frozen_string_literal: true

module TwoFactor
  # Status page and regeneration of recovery codes. Needs a verified session,
  # so a signed-in password alone cannot mint fresh codes.
  class RecoveryCodesController < BaseController
    before_action :require_verified_enrolment!

    def show; end

    def create
      @recovery_codes = TwoFactor::RecoveryCode.generate_for!(credential)
      TwoFactor::Event.record!(current_user.id, "recovery_regenerated", actor: "self")
      @continue_path = main_app.two_factor_recovery_codes_path
      render :created
    end

    private

    def require_verified_enrolment!
      return redirect_to main_app.new_two_factor_enrolment_path unless credential

      redirect_to main_app.new_two_factor_challenge_path unless TwoFactor::Policy.verified?(session, current_user)
    end
  end
end
