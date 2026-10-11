# frozen_string_literal: true

require "yaml"

module CivoraOnboard
  # The small, non-secret description of a municipality (a YAML file, see
  # config/onboarding/example.yml). Secrets never live here: the admin
  # password is read from ONBOARD_ADMIN_PASSWORD only.
  class Config
    ALLOWED_LOCALES = %w(sk en).freeze
    REGISTRATION_MODES = %w(enabled existing disabled).freeze
    HOST_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*(:\d{2,5})?\z/

    attr_reader :host, :secondary_hosts, :name, :short_name, :default_locale, :available_locales,
                :time_zone, :reference_prefix, :users_registration_mode, :ico, :admin_email, :admin_name

    def self.load(path)
      raise ArgumentError, "config file not found: #{path}" unless File.file?(path.to_s)

      data = YAML.safe_load_file(path.to_s, permitted_classes: [], aliases: false)
      raise ArgumentError, "config file must be a YAML mapping" unless data.is_a?(Hash)

      new(data)
    end

    def initialize(data)
      data = data.to_h.transform_keys(&:to_s)
      @host = data["host"].to_s.strip.downcase
      @secondary_hosts = Array(data["secondary_hosts"]).map { |h| h.to_s.strip.downcase }.compact_blank
      @default_locale = (data["default_locale"] || "sk").to_s
      @available_locales = Array(data["available_locales"] || %w(sk en)).map(&:to_s)
      @time_zone = (data["time_zone"] || "Bratislava").to_s
      @reference_prefix = data["reference_prefix"].to_s.strip.upcase
      @users_registration_mode = (data["users_registration_mode"] || "enabled").to_s
      @name = translated(data["name"])
      @short_name = data["short_name"].to_s.strip
      @admin_email = data["admin_email"].to_s.strip.downcase
      @admin_name = (data["admin_name"] || "Administrátor").to_s.strip
      @ico = Ico.validate!(data["ico"])
      validate!
    end

    # Name as a locale => text hash covering every available locale.
    def localized_name
      available_locales.index_with { |locale| name[locale] || name[default_locale] || name.values.first }
    end

    private

    def translated(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, v.to_s.strip] }.compact_blank
      else
        text = value.to_s.strip
        text.empty? ? {} : { default_locale => text }
      end
    end

    def validate!
      errors = host_errors + identity_errors + locale_errors
      errors << "users_registration_mode must be one of #{REGISTRATION_MODES.join(", ")}" unless REGISTRATION_MODES.include?(users_registration_mode)
      errors << "admin_email is required and must look like an e-mail address" unless admin_email.match?(URI::MailTo::EMAIL_REGEXP)
      raise ArgumentError, "invalid onboarding config: #{errors.join("; ")}" if errors.any?
    end

    def host_errors
      errors = []
      errors << "host is required and must be a bare host name (no scheme or path)" unless host.match?(HOST_FORMAT)
      errors << "secondary_hosts must be bare host names" unless secondary_hosts.all? { |h| h.match?(HOST_FORMAT) }
      errors
    end

    def identity_errors
      errors = []
      errors << "name is required" if name.empty?
      errors << "short_name must be 3..12 characters" unless short_name.length.between?(3, 12)
      errors << "reference_prefix is required (letters/digits)" unless reference_prefix.match?(/\A[A-Z0-9]{2,8}\z/)
      errors
    end

    def locale_errors
      errors = []
      errors << "available_locales must be a subset of #{ALLOWED_LOCALES.join(", ")}" unless available_locales.any? && (available_locales - ALLOWED_LOCALES).empty?
      errors << "default_locale must be one of available_locales" unless available_locales.include?(default_locale)
      errors << "time_zone #{time_zone.inspect} is unknown" unless ActiveSupport::TimeZone[time_zone]
      errors
    end
  end
end
