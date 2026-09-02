#!/bin/sh
# Install the repo's git hooks (gitleaks pre-commit). Idempotent.
set -eu

cd "$(dirname "$0")/.."

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "NOTE: gitleaks is not installed. The hook will warn and skip until you install it:"
  echo "  brew install gitleaks"
fi

cp scripts/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo "Installed .git/hooks/pre-commit (gitleaks secret scan)."
