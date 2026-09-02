# frozen_string_literal: true

require "test_helper"

# Failure-path semantics of the deep health check helpers (app/lib/health_checks.rb):
# any error must collapse to `false` so the endpoint can report 503 instead of 500.
class HealthChecksTest < ActiveSupport::TestCase
  test "Database.ok? is false when the connection raises" do
    ActiveRecord::Base.stub :connection, -> { raise "db unreachable" } do
      assert_not HealthChecks::Database.ok?
    end
  end

  test "Redis.ok? is true only for a PONG reply" do
    client = Minitest::Mock.new
    client.expect(:ping, "PONG")
    HealthChecks::Redis.stub :client, client do
      assert HealthChecks::Redis.ok?
    end
    client.verify
  end

  test "Redis.ok? is false when the reply is not PONG" do
    client = Minitest::Mock.new
    client.expect(:ping, "NOPE")
    HealthChecks::Redis.stub :client, client do
      assert_not HealthChecks::Redis.ok?
    end
    client.verify
  end

  test "Redis.ok? is false when the client raises" do
    HealthChecks::Redis.stub :client, UnreachableRedisClient.new do
      assert_not HealthChecks::Redis.ok?
    end
  end

  private

  # Stands in for redis-cli/connection failures; HealthChecks::Redis must
  # rescue any StandardError into `false`.
  class UnreachableRedisClient
    def ping
      raise "connection refused"
    end
  end
end
