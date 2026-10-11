# frozen_string_literal: true

# Homepage participation entry point (docs/ops/participation-navigation.md).
#
#   bin/rails "civora:home:participation[<organization_id>]"
#
# Without an id the first organization is used.
namespace :civora do
  namespace :home do
    desc "Add Decidim's highlighted-processes block to the homepage below the hero (idempotent)"
    task :participation, [:organization_id] => :environment do |_task, args|
      organization = if args[:organization_id].present?
                       Decidim::Organization.find(args[:organization_id].to_i)
                     else
                       Decidim::Organization.order(:id).first
                     end
      abort "No organization found. Create one first." unless organization

      result = CivoraHome::ParticipationBlocks.call(organization)
      state = result.block.published? ? "published" : "unpublished (left as set in the admin)"
      puts "Organization ##{organization.id} (#{organization.host}): highlighted-processes block " \
           "#{result.created ? "created" : "already present"}, #{state}."
    end
  end
end
