#!/usr/bin/env bash
#
# Runs the unit and UI tests on a tvOS simulator. Any compiler warning in the
# app or in the test targets fails the run.

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "${REPO_ROOT}"

destination="$("${REPO_ROOT}/scripts/tvos-destination.sh")"
echo "Testing on: ${destination}" >&2

result_bundle="${RESULT_BUNDLE_PATH:-${REPO_ROOT}/build/TestResults.xcresult}"
rm -rf "${result_bundle}"
mkdir -p "$(dirname "${result_bundle}")"

run_xcodebuild \
  -project "${XCODE_PROJECT}" \
  -scheme "${XCODE_SCHEME}" \
  -configuration "${XCODE_CONFIGURATION}" \
  -destination "${destination}" \
  -resultBundlePath "${result_bundle}" \
  "${WARNINGS_AS_ERRORS[@]}" \
  "${SIMULATOR_SIGNING[@]}" \
  test
