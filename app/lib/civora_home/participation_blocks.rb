# frozen_string_literal: true

module CivoraHome
  # Puts Decidim's built-in "highlighted processes" content block on an
  # organization's homepage, below the hero. Run per town with
  # `bin/rails "civora:home:participation[<organization_id>]"`
  # (lib/tasks/civora_home.rake, docs/ops/participation-navigation.md).
  #
  # Idempotent and non-destructive: the block is created only when the
  # organization has none, last in the homepage order. An existing block (also
  # one an admin unpublished, retitled or reordered in the admin UI) is left
  # exactly as it is. The block renders nothing while there are no highlighted
  # or active published processes, so running this on a contracts-only town is
  # harmless.
  class ParticipationBlocks
    SCOPE = "homepage"
    MANIFEST = "highlighted_processes"
    MAX_RESULTS = 6

    Result = Struct.new(:block, :created, keyword_init: true)

    def self.call(organization)
      new(organization).call
    end

    def initialize(organization)
      @organization = organization
    end

    def call
      scope = Decidim::ContentBlock.where(organization: @organization, scope_name: SCOPE)
      existing = scope.find_by(manifest_name: MANIFEST)
      return Result.new(block: existing, created: false) if existing

      block = Decidim::ContentBlock.create!(
        organization: @organization,
        scope_name: SCOPE,
        manifest_name: MANIFEST,
        weight: scope.maximum(:weight).to_i + 1,
        settings: { "max_results" => MAX_RESULTS },
        published_at: Time.current
      )
      Result.new(block:, created: true)
    end
  end
end
