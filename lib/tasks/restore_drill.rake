# frozen_string_literal: true

# Used by scripts/restore_drill.sh (civora-org/civora-platform#196); see
# docs/ops/restore-runbook.md. Prints counts only, never secret material.
# Exit codes: 0 decrypted, 1 could not decrypt, 3 no encrypted rows to verify.
namespace :restore_drill do
  desc "Fail unless the app can decrypt encrypted rows (checks it runs with the backup's SECRET_KEY_BASE)"
  task verify_encryption: :environment do
    result = RestoreDrill::EncryptionCheck.call
    puts result.summary
    exit(result.exit_code)
  end
end
