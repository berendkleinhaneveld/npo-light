#!/usr/bin/env bash
#
# Archives the app for a television and uploads it to App Store Connect, where
# it reaches the internal TestFlight testers and nobody else (ADR 0029).
#
# Signing is Apple's cloud-managed distribution certificate, so this machine
# needs no certificate and no profile. The archive is built unsigned and is
# signed once, for distribution, when it is exported.
#
# Authentication, in order of preference:
#   ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file) — an App Store
#   Connect API key with the Admin role, which is what CI uses;
#   otherwise the account signed in to Xcode on this Mac.
#
# BUILD_NUMBER defaults to the current UTC time, so that every upload is
# higher than the last one wherever it was made from.

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "${REPO_ROOT}"

readonly RELEASE_CONFIGURATION="Release"
build_number="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
output_dir="${REPO_ROOT}/build/testflight"
archive_path="${output_dir}/NPO light.xcarchive"
export_options="${output_dir}/ExportOptions.plist"

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

authentication=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  : "${ASC_KEY_ID:?ASC_KEY_ID is required with ASC_KEY_PATH}"
  : "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required with ASC_KEY_PATH}"
  authentication=(
    -authenticationKeyPath "${ASC_KEY_PATH}"
    -authenticationKeyID "${ASC_KEY_ID}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
  )
else
  echo "No API key given: using the account signed in to Xcode." >&2
fi

# The team is read from the project rather than repeated here. awk reads to the
# end, so that xcodebuild never writes into a closed pipe and fails the script.
team_id="$(
  xcodebuild -showBuildSettings \
    -project "${XCODE_PROJECT}" \
    -scheme "${XCODE_SCHEME}" \
    -configuration "${RELEASE_CONFIGURATION}" 2>/dev/null |
    awk '$1 == "DEVELOPMENT_TEAM" && !found { print $3; found = 1 }'
)"
if [[ -z "${team_id}" ]]; then
  echo "error: no DEVELOPMENT_TEAM in the project" >&2
  exit 1
fi

echo "Archiving build ${build_number} for team ${team_id}" >&2

run_xcodebuild \
  -project "${XCODE_PROJECT}" \
  -scheme "${XCODE_SCHEME}" \
  -configuration "${RELEASE_CONFIGURATION}" \
  -destination "generic/platform=tvOS" \
  -archivePath "${archive_path}" \
  "${WARNINGS_AS_ERRORS[@]}" \
  "CURRENT_PROJECT_VERSION=${build_number}" \
  "CODE_SIGNING_ALLOWED=NO" \
  archive

# testFlightInternalTestingOnly marks the build so that it can never be handed
# to external testers or submitted for review.
cat >"${export_options}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>upload</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${team_id}</string>
  <key>testFlightInternalTestingOnly</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST

run_xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportOptionsPlist "${export_options}" \
  -exportPath "${output_dir}/export" \
  -allowProvisioningUpdates \
  ${authentication[@]+"${authentication[@]}"}

echo "Uploaded build ${build_number}." >&2
