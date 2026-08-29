#!/usr/bin/env bash
#
# Builds the app for the tvOS simulator. Any compiler warning fails the build.

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "${REPO_ROOT}"

run_xcodebuild \
  -project "${XCODE_PROJECT}" \
  -scheme "${XCODE_SCHEME}" \
  -configuration "${XCODE_CONFIGURATION}" \
  -destination "generic/platform=tvOS Simulator" \
  "${WARNINGS_AS_ERRORS[@]}" \
  "${SIMULATOR_SIGNING[@]}" \
  build
