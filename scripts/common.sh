#!/usr/bin/env bash
#
# Shared settings for the local and CI build scripts.
# Source this file; do not execute it directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

readonly XCODE_PROJECT="NPO light.xcodeproj"
readonly XCODE_SCHEME="NPO light"
readonly XCODE_CONFIGURATION="${XCODE_CONFIGURATION:-Debug}"

# Every build must be warning free, so warnings are promoted to errors on the
# command line as well as in the project settings.
readonly WARNINGS_AS_ERRORS=(
  "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES"
  "GCC_TREAT_WARNINGS_AS_ERRORS=YES"
)

# The simulator does not need a signed binary, and CI has no signing identity.
readonly SIMULATOR_SIGNING=(
  "CODE_SIGNING_ALLOWED=NO"
  "CODE_SIGNING_REQUIRED=NO"
  "CODE_SIGN_IDENTITY="
)

# Runs xcodebuild, piping through xcbeautify when it is installed. `pipefail`
# keeps the xcodebuild exit status even when the output is piped.
run_xcodebuild() {
  echo "+ xcodebuild $*" >&2
  if command -v xcbeautify >/dev/null 2>&1; then
    local -a formatter=(xcbeautify)
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      formatter+=(--renderer github-actions)
    fi
    set -o pipefail
    xcodebuild "$@" | "${formatter[@]}"
  else
    xcodebuild "$@"
  fi
}
