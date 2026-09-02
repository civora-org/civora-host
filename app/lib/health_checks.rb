# frozen_string_literal: true

module HealthChecks
  class Database
    def self.ok?
      ActiveRecord::Base.connection.select_value("SELECT 1") == 1
    rescue StandardError
      false
    end
  end

  class Redis
    def self.ok?
      client.ping == "PONG"
    rescue StandardError
      false
    end

    def self.client
      ::Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/1"))
    end
  end
end
