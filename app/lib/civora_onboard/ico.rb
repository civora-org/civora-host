# frozen_string_literal: true

module CivoraOnboard
  # Slovak IČO (organisation identification number): 8 digits, the last one a
  # check digit. Weights 8..2 over the first seven digits, sum mod 11, check
  # digit (11 - remainder) mod 10.
  module Ico
    WEIGHTS = [8, 7, 6, 5, 4, 3, 2].freeze

    module_function

    # "00 313 271" -> "00313271"; nil when the input is blank.
    def normalize(value)
      digits = value.to_s.gsub(/\s+/, "")
      digits.presence
    end

    def format_valid?(value)
      value.to_s.match?(/\A\d{8}\z/)
    end

    def checksum_valid?(value)
      return false unless format_valid?(value)

      digits = value.chars.map(&:to_i)
      sum = WEIGHTS.each_with_index.sum { |weight, index| weight * digits[index] }
      digits.last == (11 - (sum % 11)) % 10
    end

    # Returns the normalized IČO, or raises ArgumentError with a safe message.
    def validate!(value)
      ico = normalize(value)
      raise ArgumentError, "ico is required (8 digits)" if ico.nil?
      raise ArgumentError, "ico must be exactly 8 digits" unless format_valid?(ico)
      raise ArgumentError, "ico #{ico} fails the Slovak IČO checksum (typo?)" unless checksum_valid?(ico)

      ico
    end

    # The exact line the host reads (config/initializers/contracts_sk.rb).
    def env_line(organization_id, ico)
      "CRZ_ICO_ORG_#{organization_id}=#{ico}"
    end
  end
end
