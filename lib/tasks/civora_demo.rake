# frozen_string_literal: true

# Demo seed for civora-org/civora-platform#132: the trail from a resident's
# proposal to the contract that delivered it. Idempotent; fictional data only.
# Details and the live-run steps: docs/ops/demo-proposal-to-contract.md.
#
#   bin/rails "civora:demo:proposal_to_contract[<organization_id>]"
#
# Without an id the first organization is used.
namespace :civora do
  namespace :demo do
    desc "Seed the fictional proposal -> project -> result -> contract demo story (idempotent)"
    task :proposal_to_contract, [:organization_id] => :environment do |_task, args|
      organization = if args[:organization_id].present?
                       Decidim::Organization.find(args[:organization_id].to_i)
                     else
                       Decidim::Organization.order(:id).first
                     end
      abort "No organization found. Create one first." unless organization

      outcome = CivoraDemo::ProposalToContract.call(organization)
      base = ENV["DEMO_BASE_URL"].presence || "http://#{organization.host}"

      puts "Demo scenario seeded in organization ##{organization.id} (#{organization.host})."
      puts(outcome.created.empty? ? "Nothing new: everything already existed." : "Created: #{outcome.created.size} record(s)/link(s).")
      CivoraDemo::ProposalToContract.urls(outcome).each { |label, path| puts "  #{label.ljust(10)} #{base}#{path}" }
    end
  end
end
