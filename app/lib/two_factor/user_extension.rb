# frozen_string_literal: true

module TwoFactor
  # Prepended to Decidim::User: no "remember me" for users who need a second
  # factor, so their first factor never outlives the 30 minute session timeout.
  # Devise reads this accessor to decide whether to set the remember cookie.
  module UserExtension
    def remember_me
      return nil if TwoFactor::Policy.required?(self)

      super
    end
  end
end
