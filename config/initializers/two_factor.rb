# frozen_string_literal: true

# Admin second factor (civora-org/civora-platform#164, ADR-010). Host-owned TOTP
# for admins and engine role holders. Decidim core is not forked; the touch
# points are re-verified at each Decidim upgrade (docs/ops/two-factor.md):
#
#   1. Decidim::Admin::ApplicationController  — the gate (before_action)
#   2. Decidim::Devise::SessionsController    — redirect after the password step
#   3. Decidim::User#remember_me              — no remember-me for these users
#   4. a Warden hook                           — every fresh sign-in clears the verified flag
#   5. the engine's second_factor_* seams      — defence in depth on the engine admin
#   6. Rack::Attack                            — IP throttle on the code step

# Engine seams (decidim-contracts_sk >= 1.7.1). Assigned at config time only.
Decidim::ContractsSk.second_factor_satisfied = ->(user, session) { TwoFactor::Policy.satisfied?(user, session) }
Decidim::ContractsSk.second_factor_redirect_path = lambda { |controller|
  if TwoFactor::Policy.enrolled?(controller.current_user)
    controller.main_app.new_two_factor_challenge_path
  else
    controller.main_app.new_two_factor_enrolment_path
  end
}

# A password sign-in (or a remember-me cookie, or an omniauth callback) never
# carries a previous verification over: every fresh authentication starts
# unverified. :fetch is excluded because it only reloads an existing session.
Warden::Manager.after_set_user except: :fetch do |_user, auth, opts|
  auth.raw_session.delete(TwoFactor::Policy::SESSION_KEY) if opts[:scope] == :user
end

Rails.application.config.to_prepare do
  Decidim::Admin::ApplicationController.include(TwoFactor::Gate) unless Decidim::Admin::ApplicationController < TwoFactor::Gate
  Decidim::Devise::SessionsController.prepend(TwoFactor::SignInRedirect) unless Decidim::Devise::SessionsController < TwoFactor::SignInRedirect
  Decidim::User.prepend(TwoFactor::UserExtension) unless Decidim::User < TwoFactor::UserExtension
end

# Brute-force throttle on the code step: 10 POSTs a minute per IP, on top of the
# per-credential lockout (5 wrong codes, 15 minutes). Counted in Rails.cache.
Rails.application.config.to_prepare do
  next unless defined?(Rack::Attack)

  Rack::Attack.throttle("two factor code attempts by ip", limit: 10, period: 60) do |request|
    request.ip if request.post? && %w(/two_factor/challenge /two_factor/enrolment).include?(request.path)
  end
end
