# frozen_string_literal: true

module TwoFactor
  # Operator-run lost-device reset (docs/ops/two-factor.md). Removes the user's
  # credential and recovery codes, ends their sessions and writes one audit row.
  # The user then enrols again at their next sign-in. Run only after verifying
  # the person's identity out of band.
  module Reset
    class Error < StandardError; end

    module_function

    # reason: a short free-text justification (required, stored on the audit row).
    # Returns the user.
    def call(email:, reason:, organization_id: nil)
      raise Error, "REASON is required" if reason.to_s.strip.empty?

      user = find_user(email, organization_id)
      credential = TwoFactor::Credential.find_by(decidim_user_id: user.id)
      raise Error, "User has no second factor to reset" unless credential

      ActiveRecord::Base.transaction do
        credential.destroy!
        TwoFactor::Event.record!(user.id, "reset", actor: "operator", reason: reason.strip)
      end
      user.invalidate_all_sessions!
      user
    end

    # Resets every enrolled user, e.g. after SECRET_KEY_BASE was rotated (the seeds
    # and recovery digests are keyed to it and no longer decrypt). Returns the count.
    def all(reason:)
      raise Error, "REASON is required" if reason.to_s.strip.empty?

      TwoFactor::Credential.includes(:user).find_each.sum do |credential|
        user = credential.user
        ActiveRecord::Base.transaction do
          credential.destroy!
          TwoFactor::Event.record!(credential.decidim_user_id, "reset", actor: "operator", reason: reason.strip)
        end
        user.invalidate_all_sessions!
        1
      end
    end

    def find_user(email, organization_id)
      scope = Decidim::User.where(deleted_at: nil, managed: false).where("lower(email) = ?", email.to_s.strip.downcase)
      scope = scope.where(decidim_organization_id: organization_id) if organization_id.present?
      users = scope.to_a
      raise Error, "No user found for that e-mail" if users.empty?
      raise Error, "Several organizations have that e-mail; pass ORGANIZATION_ID" if users.size > 1

      users.first
    end

    # Rows for the rollout check: every user who must use a second factor.
    def status_rows
      Decidim::User.where(deleted_at: nil, managed: false).find_each.filter_map do |user|
        next unless TwoFactor::Policy.required?(user)

        { id: user.id, email: user.email, organization_id: user.decidim_organization_id, enrolled: TwoFactor::Policy.enrolled?(user) }
      end
    end
  end
end
