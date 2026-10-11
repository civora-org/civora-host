# frozen_string_literal: true

module TwoFactor
  # One field: a six-digit authenticator code or, on the challenge, a recovery code.
  class CodeForm < Decidim::Form
    mimic :two_factor

    attribute :code, String

    validates :code, presence: true
  end
end
