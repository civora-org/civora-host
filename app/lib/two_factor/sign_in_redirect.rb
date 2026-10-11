# frozen_string_literal: true

module TwoFactor
  # Prepended to Decidim::Devise::SessionsController: right after the password
  # step, a user who needs a second factor lands on the challenge (or on
  # enrolment) instead of the home page. The stored return location is left in
  # place so the challenge can send the user on to where they were going.
  module SignInRedirect
    def after_sign_in_path_for(user)
      return super unless TwoFactor::Policy.required?(user)

      if TwoFactor::Policy.enrolled?(user)
        main_app.new_two_factor_challenge_path
      else
        main_app.new_two_factor_enrolment_path
      end
    end
  end
end
