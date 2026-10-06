# frozen_string_literal: true

# Prepares an organization for the public demo server (docs/ops/demo-server.md),
# called by bin/demo-deploy after the migrations and the base seed. Idempotent.
# Refuses to run unless DEMO_MODE=1, so it can never touch a pilot database.
#
#   DEMO_ADMIN_EMAIL=... DEMO_ADMIN_PASSWORD=... \
#     bin/rails "civora:demo:prepare_server[<organization_id>]"
#
# It sets the Slovak default locale and the omnipresent "DEMO" banner on the
# organization, and creates or updates one demo admin. The password comes from
# the environment only and is never printed.
namespace :civora do
  namespace :demo do
    desc "Prepare the organization and the demo admin for the public demo server (needs DEMO_MODE=1)"
    task :prepare_server, [:organization_id] => :environment do |_task, args|
      abort "Refusing to run: DEMO_MODE=1 is not set." unless ENV["DEMO_MODE"] == "1"

      organization = if args[:organization_id].present?
                       Decidim::Organization.find(args[:organization_id].to_i)
                     else
                       Decidim::Organization.order(:id).first
                     end
      abort "No organization found. Run db:seed first." unless organization

      CivoraDemo::ServerPreparation.call(
        organization,
        admin_email: ENV.fetch("DEMO_ADMIN_EMAIL", nil),
        admin_password: ENV.fetch("DEMO_ADMIN_PASSWORD", nil)
      )
      puts "Demo server prepared for organization ##{organization.id} (#{organization.host})."
    end
  end
end
