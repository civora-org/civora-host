# frozen_string_literal: true

# Decidim 0.32 derives encryption keys with SHA256 (0.31: SHA1) and
# `decidim:upgrade:encryption` re-saves only Decidim's own records. This adds
# the host's TOTP seeds to that task, so the one documented upgrade command
# covers them. It can also be run alone. See docs/ops/decidim-0.32-upgrade.md.
namespace :civora do
  namespace :upgrade do
    desc "Re-encrypt every two-factor seed with the current key derivation (SHA256)"
    task encryption: :environment do
      puts "Re-encrypted #{TwoFactor::Reencryption.call} two-factor seed(s)."
    end
  end
end

Rake::Task["decidim:upgrade:encryption"].enhance(["civora:upgrade:encryption"]) if Rake::Task.task_defined?("decidim:upgrade:encryption")
