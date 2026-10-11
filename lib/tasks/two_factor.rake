# frozen_string_literal: true

# Admin second factor operations (civora-org/civora-platform#164, ADR-010).
# See docs/ops/two-factor.md.
namespace :two_factor do
  desc "Lost-device reset: EMAIL=… REASON=… [ORGANIZATION_ID=…] removes the second factor and ends the user's sessions"
  task reset: :environment do
    user = TwoFactor::Reset.call(email: ENV.fetch("EMAIL", nil), reason: ENV.fetch("REASON", nil), organization_id: ENV.fetch("ORGANIZATION_ID", nil))
    puts "Second factor reset for user ##{user.id}. They enrol again at their next sign-in."
  rescue TwoFactor::Reset::Error => e
    abort "two_factor:reset failed: #{e.message}"
  end

  desc "Reset EVERY enrolled user (after a SECRET_KEY_BASE rotation): REASON=…"
  task reset_all: :environment do
    puts "Reset #{TwoFactor::Reset.all(reason: ENV.fetch("REASON", nil))} second factors. Everyone enrols again at their next sign-in."
  rescue TwoFactor::Reset::Error => e
    abort "two_factor:reset_all failed: #{e.message}"
  end

  desc "List admins and role holders and whether they have enrolled (no secrets printed)"
  task status: :environment do
    rows = TwoFactor::Reset.status_rows
    puts "id\torganization\tenrolled\temail"
    rows.each { |r| puts [r[:id], r[:organization_id], r[:enrolled] ? "yes" : "NO", r[:email]].join("\t") }
    puts "#{rows.count { |r| !r[:enrolled] }} of #{rows.size} not enrolled"
  end
end
