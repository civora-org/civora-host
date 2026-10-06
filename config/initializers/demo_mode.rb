# frozen_string_literal: true

# Public demo server guard (docs/ops/demo-server.md). Active only when
# DEMO_MODE=1, which only compose.demo.yml sets. Outgoing mail is written to
# files inside the container instead of being sent, so nobody ever receives
# real email from a demo (password resets, invitations, search alerts). Without
# DEMO_MODE this file is a no-op and the production SMTP settings apply.
if ENV["DEMO_MODE"] == "1"
  ActiveSupport.on_load(:action_mailer) do
    self.delivery_method = :file
    self.file_settings = { location: Rails.root.join("tmp/demo-mails").to_s }
    self.perform_deliveries = true
    self.raise_delivery_errors = false
  end
end
