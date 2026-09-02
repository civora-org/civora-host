# frozen_string_literal: true

# Deep health endpoint used by monitoring (civora-org/civora-platform#51).
# Unlike the shallow /up (boot signal), /healthz verifies connectivity to
# the database and Redis. Returns 503 with a JSON status payload when any
# dependency is unreachable.
class HealthController < ApplicationController
  skip_forgery_protection

  def show
    checks = {
      "database" => HealthChecks::Database.ok? ? "ok" : "error",
      "redis" => HealthChecks::Redis.ok? ? "ok" : "error"
    }
    healthy = checks.values.all? { |state| state == "ok" }

    render json: {
      status: healthy ? "ok" : "error",
      checks: checks
    }, status: healthy ? :ok : :service_unavailable
  end
end
