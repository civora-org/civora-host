# frozen_string_literal: true

# Accessibility statement (civora-org/civora-platform#133): creates or updates
# the Decidim static page "accessibility" (sk + en) per organization.
# Idempotent. Details: docs/ops/accessibility-statement.md.
#
#   ACCESSIBILITY_CONTACT_EMAIL=access@example.org \
#     bin/rails "civora:accessibility_statement:publish[<organization_id>]"
#
# Without an id every organization is updated. Without the variable the
# organization's own sender address is used, then a visible placeholder.
namespace :civora do
  namespace :accessibility_statement do
    desc "Create or update the accessibility statement static page (sk + en), per organization (idempotent)"
    task :publish, [:organization_id] => :environment do |_task, args|
      organizations = if args[:organization_id].present?
                        Decidim::Organization.where(id: args[:organization_id].to_i)
                      else
                        Decidim::Organization.order(:id)
                      end
      abort "No organization found." if organizations.empty?

      organizations.each do |organization|
        result = AccessibilityStatement.call(organization, contact_email: ENV.fetch("ACCESSIBILITY_CONTACT_EMAIL", nil))
        contact = result.contact_email.presence || "none (placeholder in the text)"
        puts "#{result.created ? "Created" : "Updated"} /pages/#{AccessibilityStatement::SLUG} in organization " \
             "##{organization.id} (#{organization.host}); contact: #{contact}."
      end
    end
  end
end
