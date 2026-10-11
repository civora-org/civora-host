# frozen_string_literal: true

module TwoFactor
  # Append-only audit row. Never stores a secret, a code or an e-mail address.
  class Event < ApplicationRecord
    KINDS = %w(enrolled recovery_used recovery_regenerated locked reset).freeze
    ACTORS = %w(self operator).freeze

    validates :kind, inclusion: { in: KINDS }
    validates :actor, inclusion: { in: ACTORS }

    before_update { raise ActiveRecord::ReadOnlyRecord }
    before_destroy { raise ActiveRecord::ReadOnlyRecord }

    def self.record!(user_id, kind, actor:, reason: nil)
      create!(decidim_user_id: user_id, kind:, actor:, reason: reason&.truncate(200))
    end
  end
end
