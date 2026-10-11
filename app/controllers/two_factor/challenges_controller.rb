# frozen_string_literal: true

module TwoFactor
  # Step two of sign-in for admins and role holders: an authenticator code, or
  # a single-use recovery code.
  class ChallengesController < BaseController
    before_action :require_enrolment!
    before_action :skip_when_verified!

    def new
      @form = empty_code_form
    end

    def create
      @form = code_form
      return render(:new, status: :unprocessable_entity) unless @form.valid?

      result = verify(@form.code)
      return verification_failed(@form, result, :new) unless result == :ok

      TwoFactor::Policy.mark_verified!(session, current_user)
      redirect_to after_second_factor_path, **recovery_notice
    end

    private

    def require_enrolment!
      redirect_to main_app.new_two_factor_enrolment_path unless credential
    end

    def skip_when_verified!
      redirect_to after_second_factor_path if TwoFactor::Policy.verified?(session, current_user)
    end

    def totp_shaped?(code)
      code.gsub(/\s/, "").match?(/\A\d+\z/)
    end

    def verify(code)
      return credential.verify_totp(code) if totp_shaped?(code)

      credential.verify_recovery_code(code).tap do |result|
        if result == :ok
          @recovery_used = true
          TwoFactor::Event.record!(current_user.id, "recovery_used", actor: "self")
        end
      end
    end

    def recovery_notice
      return {} unless @recovery_used

      { notice: t("two_factor.recovery_used", count: recovery_codes_remaining) }
    end
  end
end
