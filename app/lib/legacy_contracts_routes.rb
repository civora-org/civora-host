# frozen_string_literal: true

# Un-prefixed /contracts/... URLs from before Decidim 0.32 (locale in the path;
# see config/routes.rb and docs/ops/decidim-0.32-upgrade.md).
module LegacyContractsRoutes
  MOUNT = "/contracts"

  module_function

  # The locale a legacy URL is sent to: an explicit `locale` parameter, the
  # signed-in user's, the session's, else the ORGANIZATION's default.
  # Decidim::LocaleRouterDetector would fall back to I18n.locale before the
  # organization default, and at that point in the request (before Decidim's
  # locale switcher has run) that is the application default, "en": a
  # Slovak organization's bookmark would land on the English site.
  def locale_for(request)
    organization = request.env["decidim.current_organization"] || Decidim
    available = organization.available_locales.map(&:to_s)
    requested(request).find { |candidate| available.include?(candidate) } || organization.default_locale.to_s
  end

  def requested(request)
    [request.parameters[:locale], request.env["warden"]&.user("user")&.locale, request.session[:user_locale]]
      .grep(String)
  end

  # Permanent redirect target of a legacy GET: the prefixed path, query kept,
  # `locale` dropped (Decidim::Routes::LocaleRedirects#locale_redirect).
  # The remainder is percent-escaped again because the router hands it over
  # decoded, and a space or a stray byte in a redirect location raises.
  def escaped_path(rest)
    "#{MOUNT}/#{Rack::Utils.escape_path(rest.to_s.scrub(""))}"
  end

  # A legacy POST is served by the engine directly, with no redirect: mail
  # clients must not follow redirects on the one-click List-Unsubscribe POST
  # (RFC 8058), and a 308 would not help them. The request is rewritten as
  # if it had arrived under the locale scope: SCRIPT_NAME is the prefixed
  # mount, PATH_INFO the remainder, and the locale a path parameter, which is
  # what the scope would have supplied. The locale comes from #locale_for, so a forged value
  # falls back to the organization's default.
  def forward_post(env)
    request = ActionDispatch::Request.new(env)
    locale = locale_for(request)
    rewritten = env.merge(
      "SCRIPT_NAME" => "#{env["SCRIPT_NAME"]}/#{locale}#{MOUNT}",
      "PATH_INFO" => env["PATH_INFO"].delete_prefix(MOUNT),
      "action_dispatch.request.path_parameters" => { locale: locale.to_s }
    )
    Decidim::ContractsSk::Engine.call(rewritten)
  end
end
