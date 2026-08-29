#!/usr/bin/env bash
#
# Lints the Swift sources. Warnings are treated as errors (`--strict`), so any
# violation fails the run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

"${REPO_ROOT}/scripts/check-lint-exceptions.sh"

# On Linux the SwiftLint release ships a statically linked binary under a
# different name; it runs every rule except the four that need SourceKit, and
# says so on stderr. See "Linting on Linux" in AGENTS.md.
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint_bin=swiftlint
elif command -v swiftlint-static >/dev/null 2>&1; then
  swiftlint_bin=swiftlint-static
else
  echo "error: swiftlint is not installed. Install the latest version with:" >&2
  echo "       macOS: brew install swiftlint" >&2
  echo "       Linux: ./scripts/install-swiftlint-linux.sh" >&2
  exit 1
fi

echo "Using SwiftLint $("${swiftlint_bin}" version) (${swiftlint_bin})" >&2

lint_args=(lint --strict)
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  lint_args+=(--reporter github-actions-logging)
fi

"${swiftlint_bin}" "${lint_args[@]}"
