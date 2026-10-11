# frozen_string_literal: true

module TwoFactor
  # Before-action included into Decidim::Admin::ApplicationController (and so
  # into every Decidim admin and engine admin controller, the engine's
  # included). A signed-in admin or role holder who has not passed the second
  # factor in this session is sent to enrol or to the challenge; everyone else
  # is untouched. Participants never reach this code.
  module Gate
    extend ActiveSupport::Concern

    included do
      before_action :require_two_factor!
    end

    private

    def require_two_factor!
      user = current_user
      return unless TwoFactor::Policy.required?(user)
      return if TwoFactor::Policy.enrolled?(user) && TwoFactor::Policy.verified?(session, user)

      store_location_for(:user, request.fullpath) if request.get? && request.format.html?
      flash[:alert] = I18n.t("two_factor.gate.required")
      redirect_to TwoFactor::Policy.enrolled?(user) ? main_app.new_two_factor_challenge_path : main_app.new_two_factor_enrolment_path
    end
  end
end
