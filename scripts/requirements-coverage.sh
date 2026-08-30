#!/usr/bin/env bash
#
# Maps the requirements in docs/requirements/ onto the tests that prove them.
#
# A test claims a requirement by naming its identifier, either in the test's
# display name -- @Test("FR-SEARCH-03: typing is not blocked") -- or in a
# `// Requirement: FR-SEARCH-03` comment. See docs/requirements/README.md.
#
# The run fails when:
#   * a test names an identifier that does not exist (a typo, or a renumbering);
#   * a requirement marked Implemented is named by no test and declares no
#     other verification;
#   * an identifier is defined twice, has no status, or has an unknown one.
#
# A requirement that is Accepted but untested is work not done yet, not an
# error, so it does not fail the run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

readonly REQUIREMENTS_DIR="docs/requirements"
readonly ID_PATTERN='(FR|NFR)-[A-Z][A-Z0-9]*-[0-9][0-9]'
TEST_DIRS=("NPO lightTests" "NPO lightUITests")

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# 1. Every requirement, as: id <TAB> status <TAB> verified-by <TAB> file.
#    Parse errors are emitted on the same stream, prefixed with ERR.
awk -v pattern="^${ID_PATTERN}\$" '
  BEGIN { verified = "no" }
  function flush() {
    if (id != "") {
      if (status == "")
        printf("ERR\t%s has no Status line (%s)\n", id, FILENAME)
      else
        printf("REQ\t%s\t%s\t%s\t%s\n", id, status, verified, FILENAME)
    }
    id = ""; status = ""; verified = "no"
  }
  /^## / {
    flush()
    if ($2 ~ pattern) id = $2
    next
  }
  /^- \*\*Status:\*\*/ {
    if (id != "") { status = $3 }
    next
  }
  /^- \*\*Verified by:\*\*/ {
    if (id != "") { verified = "yes" }
    next
  }
  END { flush() }
' "${REQUIREMENTS_DIR}"/*.md > "${work}/parsed"

grep '^ERR' "${work}/parsed" | cut -f2- > "${work}/errors" || true
grep '^REQ' "${work}/parsed" | cut -f2- > "${work}/requirements" || true
cut -f1 "${work}/requirements" | sort > "${work}/defined"

# 2. Every identifier the tests name.
grep -rhoE "${ID_PATTERN}" --include='*.swift' "${TEST_DIRS[@]}" 2>/dev/null \
  | sort -u > "${work}/referenced" || true
touch "${work}/referenced"

status=0

report() {
  echo "error: $1" >&2
  status=1
}

# 3. Parse errors found above.
while IFS= read -r line; do
  [[ -n "${line}" ]] && report "${line}"
done < "${work}/errors"

# 4. An identifier defined more than once.
duplicates="$(uniq -d "${work}/defined")"
if [[ -n "${duplicates}" ]]; then
  while IFS= read -r id; do
    report "${id} is defined more than once."
  done <<< "${duplicates}"
fi

# 5. An unknown status value.
while IFS=$'\t' read -r id req_status _verified file; do
  case "${req_status}" in
    Proposed|Accepted|Implemented|Deferred|Superseded) ;;
    *) report "${id} has an unknown status '${req_status}' (${file})." ;;
  esac
done < "${work}/requirements"

# 6. A test naming an identifier that does not exist.
unknown="$(comm -13 <(sort -u "${work}/defined") "${work}/referenced")"
if [[ -n "${unknown}" ]]; then
  while IFS= read -r id; do
    report "the tests name ${id}, which no requirement defines."
  done <<< "${unknown}"
fi

# 7. An Implemented requirement that nothing verifies.
while IFS=$'\t' read -r id req_status verified file; do
  if [[ "${req_status}" == "Implemented" && "${verified}" == "no" ]] \
    && ! grep -qx "${id}" "${work}/referenced"; then
    report "${id} is marked Implemented but no test names it (${file})."
  fi
done < "${work}/requirements"

# 8. The summary, always printed.
total="$(wc -l < "${work}/requirements" | tr -d ' ')"
echo "Requirements in ${REQUIREMENTS_DIR}: ${total}"
for value in Proposed Accepted Implemented Deferred Superseded; do
  count="$(cut -f2 "${work}/requirements" | grep -cx "${value}" || true)"
  [[ "${count}" -gt 0 ]] && printf '  %-12s %s\n' "${value}" "${count}"
done
echo "Identifiers named by tests: $(wc -l < "${work}/referenced" | tr -d ' ')"

if [[ "${status}" -ne 0 ]]; then
  echo "Requirement coverage check failed." >&2
fi

exit "${status}"
