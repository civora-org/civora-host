# frozen_string_literal: true

module TwoFactor
  # First-time enrolment. Only reachable while the user has no confirmed
  # credential: an enrolled user cannot re-enrol with a password alone, so a
  # phished password cannot replace the authenticator. Lost device: operator
  # reset (docs/ops/two-factor.md).
  class EnrolmentsController < BaseController
    before_action :redirect_when_enrolled!
    before_action :load_pending_credential

    def new
      @form = empty_code_form
    end

    def create
      @form = code_form
      return render(:new, status: :unprocessable_content) unless @form.valid?

      result = @pending.confirm!(@form.code)
      return verification_failed(@form, result, :new) unless result == :ok

      @recovery_codes = TwoFactor::RecoveryCode.generate_for!(@pending)
      TwoFactor::Event.record!(current_user.id, "enrolled", actor: "self")
      TwoFactor::Policy.mark_verified!(session, current_user)
      @continue_path = after_second_factor_path
      render "two_factor/recovery_codes/created"
    end

    private

    def redirect_when_enrolled!
      return unless credential

      redirect_to TwoFactor::Policy.verified?(session, current_user) ? main_app.two_factor_recovery_codes_path : main_app.new_two_factor_challenge_path
    end

    # The pending seed is kept between page loads, so a refresh does not
    # invalidate a QR code that was already scanned.
    def load_pending_credential
      @pending = TwoFactor::Credential.find_by(decidim_user_id: current_user.id) ||
                 TwoFactor::Credential.build_pending(current_user).tap(&:save!)
      @qr = TwoFactor::QrPath.call(@pending.provisioning_uri)
      @secret_groups = @pending.otp_secret.scan(/.{1,4}/).join(" ")
    end
  end
end
