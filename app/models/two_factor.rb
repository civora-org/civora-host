# frozen_string_literal: true

# Admin second factor (civora-org/civora-platform#164, ADR-010). Host-owned
# TOTP; Decidim core and its tables are not patched. See docs/ops/two-factor.md.
module TwoFactor
  def self.table_name_prefix
    "civora_two_factor_"
  end
end
