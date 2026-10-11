# frozen_string_literal: true

# Resident entry points to the participatory processes (header link, hero CTA).
#
# Civora is contracts-first, so the processes are surfaced only when the
# organization actually has some a visitor can open. "Has some" is the same
# set Decidim's own /processes index lists (organization, visible for the
# user, published); an empty set makes that index answer 404, so a link to it
# would be a dead end.
#
# The answer is memoized in the Rack env, so the desktop header, the hero and
# any other caller cost one query per request.
module ParticipationNavigation
  ENV_KEY = "civora.participation_navigation.processes"

  module_function

  def processes?(organization, user, env)
    return false if organization.nil?

    key = [organization.id, user&.id]
    cached = env[ENV_KEY]
    return cached[1] if cached && cached[0] == key

    result = Decidim::ParticipatoryProcesses::OrganizationPublishedParticipatoryProcesses
             .new(organization, user).query.exists?
    env[ENV_KEY] = [key, result]
    result
  end

  def path
    Decidim::ParticipatoryProcesses::Engine.routes.url_helpers.participatory_processes_path
  end
end
