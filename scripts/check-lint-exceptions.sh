#!/usr/bin/env bash
#
# Enforces the "no lint exceptions" policy from AGENTS.md.
#
# Rule exceptions -- inline `swiftlint:disable` comments, `disabled_rules`, or
# `excluded` paths in .swiftlint.yml -- are only allowed with explicit written
# approval from the repository owner. Until that approval exists this check
# fails the build, so an exception can never be introduced silently.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

status=0

# 1. Inline disable comments anywhere in the Swift sources.
inline_disables="$(grep -rIn --include='*.swift' -e 'swiftlint:disable' . || true)"
if [[ -n "${inline_disables}" ]]; then
  echo "error: inline SwiftLint disable comments are not allowed:" >&2
  echo "${inline_disables}" >&2
  status=1
fi

# 2. Rules switched off or paths skipped in the SwiftLint configuration.
for key in disabled_rules excluded; do
  if grep -qE "^[[:space:]]*${key}[[:space:]]*:" .swiftlint.yml; then
    echo "error: .swiftlint.yml must not define '${key}'." >&2
    status=1
  fi
done

# 3. `only_rules` silently disables every rule that is not listed.
if grep -qE '^[[:space:]]*only_rules[[:space:]]*:' .swiftlint.yml; then
  echo "error: .swiftlint.yml must not define 'only_rules'." >&2
  status=1
fi

if [[ ${status} -ne 0 ]]; then
  cat >&2 <<'MESSAGE'

The linting rules apply to all code without exception. If a rule genuinely
does not fit this project, ask the repository owner in the pull request, and
record the approved exception in an ADR under docs/adr/ before adding it.
MESSAGE
fi

exit ${status}
