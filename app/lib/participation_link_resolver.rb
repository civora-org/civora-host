# frozen_string_literal: true

# Host side of the contract <-> participation link (ADR-009,
# civora-org/civora-platform#130).
#
# The engine owns the join (Decidim::ContractsSk::ContractLink) and the
# config-time `link_target_resolver` seam; the host decides what a target is
# and how to present it. This resolver is wired in
# config/initializers/contracts_sk.rb.
#
# Tenant safety: the engine hands over the link, whose target row is loaded by
# bare polymorphic id. The resolver therefore answers nil unless the target's
# organization is the contract's organization, so an id from another tenant
# can never be presented. It also answers nil unless the target is publicly
# reachable (component and participatory space published, space not private),
# because the label is rendered on the public contract page.
#
# Supported targets: Decidim::Accountability::Result and
# Decidim::Budgets::Project. Returns { label:, url: } or nil.
module ParticipationLinkResolver
  TARGET_TYPES = %w(Decidim::Accountability::Result Decidim::Budgets::Project).freeze

  class Translator
    include Decidim::TranslatableAttributes
  end

  module_function

  def call(link)
    return nil unless TARGET_TYPES.include?(link.target_type.to_s)

    target = link.target
    organization = link.contract&.organization
    return nil if target.nil? || organization.nil?
    return nil unless same_organization?(target, organization)
    return nil unless publicly_visible?(target)

    label = Translator.new.translated_attribute(target.title, organization).to_s.strip
    return nil if label.empty?

    { label: label, url: path_for(target) }
  end

  def same_organization?(target, organization)
    target.organization&.id == organization.id
  end

  def publicly_visible?(target)
    component = target.component
    space = target.participatory_space
    component&.published? && space&.visible?
  end

  # A relative path: the contract page and the target live on the same host.
  # Budgets projects are nested under their budget.
  def path_for(target)
    subject = target.is_a?(Decidim::Budgets::Project) ? [target.budget, target] : target
    Decidim::ResourceLocatorPresenter.new(subject).path
  end
end
