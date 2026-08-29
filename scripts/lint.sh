#!/usr/bin/env bash
#
# Lints the Swift sources. Warnings are treated as errors (`--strict`), so any
# violation fails the run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

"${REPO_ROOT}/scripts/check-lint-exceptions.sh"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint is not installed. Install the latest version with:" >&2
  echo "       brew install swiftlint" >&2
  exit 1
fi

echo "Using $(swiftlint version | sed 's/^/SwiftLint /')" >&2

lint_args=(lint --strict)
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  lint_args+=(--reporter github-actions-logging)
fi

swiftlint "${lint_args[@]}"
