# frozen_string_literal: true

Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Decidim 0.32 puts the locale in the URL (/sk/processes/...), so the
  # contracts engine is mounted inside the same locale scope as the core
  # engine. Without it the language chooser (a core controller that redirects to
  # the path-prefixed URL) ends in a 404 on engine pages. The legacy
  # un-prefixed paths (bookmarks, open-data URLs, CRZ handoff links) are
  # redirected permanently, query string kept. `format: false` keeps the
  # extension of a stored link (/contracts/export.csv); without it the glob
  # swallows ".csv". Declared before the core engine mount; the POST route
  # forwards into the engine without a redirect (see LegacyContractsRoutes). Reference:
  # decidim-contracts_sk docs/locale-urls.md (civora-org/civora-platform#183, #186).
  extend Decidim::Routes::LocaleRedirects

  scope "/:locale", **locale_scope_options do
    mount Decidim::ContractsSk::Engine, at: "/contracts"
  end

  get "/contracts", to: redirect { |params, request|
    locale_redirect(params.merge(locale: LegacyContractsRoutes.locale_for(request)), request, "/contracts")
  }
  get "/contracts/*rest", format: false, to: redirect { |params, request|
    locale_redirect(params.merge(locale: LegacyContractsRoutes.locale_for(request)), request, LegacyContractsRoutes.escaped_path(params[:rest]))
  }
  # POSTs from pages and e-mails that predate the upgrade (the one-click
  # List-Unsubscribe-Post, a stale form) are served in place, not redirected.
  post "/contracts/*rest", format: false, to: LegacyContractsRoutes.method(:forward_post)

  mount Decidim::Core::Engine => "/"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  # Deep health check: verifies database and Redis connectivity (civora-org/civora-platform#51)
  get "healthz" => "health#show"

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", :as => :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", :as => :pwa_manifest

  # Admin second factor (civora-org/civora-platform#164, ADR-010). Host-owned
  # pages; the gate itself lives in app/lib/two_factor/gate.rb.
  get "two_factor/challenge", to: "two_factor/challenges#new", as: :new_two_factor_challenge
  post "two_factor/challenge", to: "two_factor/challenges#create", as: :two_factor_challenge
  get "two_factor/enrolment", to: "two_factor/enrolments#new", as: :new_two_factor_enrolment
  post "two_factor/enrolment", to: "two_factor/enrolments#create", as: :two_factor_enrolment
  resource :two_factor_recovery_codes, only: [:show, :create], controller: "two_factor/recovery_codes", path: "two_factor/recovery_codes"

  # Defines the root path route ("/")
  # root "posts#index"
end
