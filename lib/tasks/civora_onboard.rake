# frozen_string_literal: true

# Municipality onboarding (civora-org/civora-platform#140, ADR-011).
# Runbook and verification checklist: docs/ops/onboard-municipality.md.
#
#   bin/rails "civora:onboard:organization[config/onboarding/<city>.yml]"   # DRY_RUN=1 to preview
#   bin/rails "civora:onboard:crz_sync[<org id>,<since ISO8601>]"           # first sync, resumes on 429
#   bin/rails "civora:onboard:verify[<org id>]"
#
# Secrets come from the environment only and are never printed:
# ONBOARD_ADMIN_PASSWORD.
namespace :civora do
  namespace :onboard do
    desc "Create or converge a municipality's organization and first admin from a YAML file (idempotent; DRY_RUN=1 previews)"
    task :organization, [:config_path] => :environment do |_task, args|
      abort "Usage: bin/rails \"civora:onboard:organization[<config.yml>]\" (DRY_RUN=1 to preview)" if args[:config_path].blank?

      config = begin
        CivoraOnboard::Config.load(args[:config_path])
      rescue ArgumentError, Psych::Exception => e
        abort "ERROR: #{e.message}"
      end

      dry_run = ENV["DRY_RUN"] == "1"
      password = ENV.fetch("ONBOARD_ADMIN_PASSWORD", "")
      puts(dry_run ? "DRY RUN (nothing is written)" : "Onboarding #{config.host}")

      result = CivoraOnboard::OrganizationProvisioner.call(config, admin_password: password, dry_run: dry_run)
      organization = result.organization
      id = organization&.id

      if dry_run
        puts(if organization
               "Organization ##{id} exists for #{config.host}; would change: #{result.changes.join(", ").presence || "nothing"}"
             else
               "Would create the organization for #{config.host}"
             end)
        puts "Admin #{config.admin_email}: #{result.admin_status}"
      else
        puts "Organization ##{id} (#{config.host}): #{result.created ? "created" : "already existed"}; updated: #{result.changes.join(", ").presence || "nothing"}"
        puts "Admin #{config.admin_email}: #{result.admin_status}"
        puts "  (no ONBOARD_ADMIN_PASSWORD given: Decidim's invitation e-mail is the way in)" if result.admin_status == :invited
      end

      puts
      puts "Add this line to the stack's .env (then recreate app and scheduler so they read it):"
      puts "  #{CivoraOnboard::Ico.env_line(id || "<organization id>", config.ico)}"
      current = id && ENV.fetch("CRZ_ICO_ORG_#{id}", nil)
      puts "  WARNING: CRZ_ICO_ORG_#{id} is currently #{current} in this process, not #{config.ico}" if current.present? && current != config.ico
      puts "Next: bin/rails \"civora:onboard:crz_sync[#{id || "<organization id>"},<since>]\" and civora:onboard:verify[#{id || "<organization id>"}]"
    end

    desc "First CRZ sync for an organization; resumes after ekosystem rate-limit stops (SINCE arg or ONBOARD_SINCE, default 30 days ago)"
    task :crz_sync, [:organization_id, :since] => :environment do |_task, args|
      organization = Decidim::Organization.find_by(id: args[:organization_id].to_i)
      abort "Organization ##{args[:organization_id]} not found" unless organization

      ico = Decidim::ContractsSk.crz_organization_ico(organization)
      abort "CRZ_ICO_ORG_#{organization.id} is not set in this process. Add it to .env and recreate the container." unless ico
      abort "CRZ_ICO_ORG_#{organization.id}=#{ico} is not a valid IČO" unless CivoraOnboard::Ico.checksum_valid?(ico)

      since = args[:since].presence || ENV["ONBOARD_SINCE"].presence || 30.days.ago.utc.iso8601
      begin
        Time.iso8601(since)
      rescue ArgumentError
        abort "SINCE is not a valid ISO8601 timestamp: #{since}"
      end

      outcome = CivoraOnboard::SyncResume.new(organization_id: organization.id, since: since).call
      puts "CRZ first sync for organization ##{organization.id}: #{outcome.status} after #{outcome.passes} pass(es), last since #{outcome.last_since}"
      exit 1 unless outcome.complete?
    end

    desc "Checklist of the machine-checkable onboarding conditions for an organization"
    task :verify, [:organization_id] => :environment do |_task, args|
      organization = Decidim::Organization.find_by(id: args[:organization_id].to_i)
      abort "Organization ##{args[:organization_id]} not found" unless organization

      checks = CivoraOnboard::Verification.call(organization)
      checks.each { |check| puts "[#{check.ok ? "ok" : "FAIL"}] #{check.label}: #{check.detail}" }
      exit 1 unless checks.all?(&:ok)
    end
  end
end
