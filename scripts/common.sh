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
# (Not marked readonly: bash 3.2, which macOS ships, cannot do that for arrays.)
WARNINGS_AS_ERRORS=(
  "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES"
  "GCC_TREAT_WARNINGS_AS_ERRORS=YES"
)

# Simulator builds are signed ad hoc: the identity "-" needs no certificate, so
# CI can do it, and without a signature the app has no Keychain at all — every
# call fails with errSecMissingEntitlement (ADR 0013). The team and the
# automatic style are cleared so that nothing here reaches for an account.
SIMULATOR_SIGNING=(
  "CODE_SIGN_IDENTITY=-"
  "CODE_SIGN_STYLE=Manual"
  "CODE_SIGNING_REQUIRED=NO"
  "DEVELOPMENT_TEAM="
  "PROVISIONING_PROFILE_SPECIFIER="
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
