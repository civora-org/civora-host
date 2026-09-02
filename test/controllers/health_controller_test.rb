# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "GET /up returns ok" do
    get "/up"
    assert_response :ok
  end

  test "GET /healthz reports ok when all checks pass" do
    HealthChecks::Database.stub :ok?, true do
      HealthChecks::Redis.stub :ok?, true do
        get "/healthz"
      end
    end
    assert_response :ok
    body = response.parsed_body
    assert_equal "ok", body["status"]
    assert_equal({ "database" => "ok", "redis" => "ok" }, body["checks"])
  end

  test "GET /healthz returns 503 when database is unreachable" do
    HealthChecks::Database.stub :ok?, false do
      HealthChecks::Redis.stub :ok?, true do
        get "/healthz"
      end
    end
    assert_response :service_unavailable
    body = response.parsed_body
    assert_equal "error", body["status"]
    assert_equal "error", body["checks"]["database"]
    assert_equal "ok", body["checks"]["redis"]
  end

  test "GET /healthz returns 503 when redis is unreachable" do
    HealthChecks::Database.stub :ok?, true do
      HealthChecks::Redis.stub :ok?, false do
        get "/healthz"
      end
    end
    assert_response :service_unavailable
    body = response.parsed_body
    assert_equal "error", body["status"]
    assert_equal "ok", body["checks"]["database"]
    assert_equal "error", body["checks"]["redis"]
  end

  test "health check classes report real database state" do
    assert HealthChecks::Database.ok?
  end

  test "GET /healthz is reachable by monitoring user agents (allow_browser must not 406 probes)" do
    ["blackbox_exporter/0.25.0", "curl/8.7.1", "Prometheus/2.53.1"].each do |user_agent|
      HealthChecks::Database.stub :ok?, true do
        HealthChecks::Redis.stub :ok?, true do
          get "/healthz", headers: { "User-Agent" => user_agent }
          assert_response :ok, "user agent #{user_agent.inspect} must reach /healthz"
        end
      end
    end
  end

  test "GET /up is reachable by monitoring user agents" do
    get "/up", headers: { "User-Agent" => "blackbox_exporter/0.25.0" }
    assert_response :ok
  end

  test "POST /healthz never reaches the health controller (GET-only, no state changes)" do
    # Decidim::Core::Engine is mounted at "/" and renders its own 404 for
    # unmatched paths, so nothing is raised — but the request must not turn
    # into a 2xx/3xx against the health controller.
    post "/healthz"
    assert_response :not_found
  end
end
