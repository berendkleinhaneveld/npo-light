#!/usr/bin/env bash
#
# Prints an `xcodebuild -destination` string for an available tvOS simulator.
# Override the choice by setting DESTINATION in the environment.

set -euo pipefail

if [[ -n "${DESTINATION:-}" ]]; then
  echo "${DESTINATION}"
  exit 0
fi

# Devices are grouped per runtime ("-- tvOS 26.2 --"), oldest runtime first,
# so the last match is a device on the newest installed tvOS runtime.
udid="$(xcrun simctl list devices available \
  | awk '/^-- tvOS /{ in_tvos = 1; next } /^-- /{ in_tvos = 0 } in_tvos' \
  | grep -Eo '[0-9A-Fa-f-]{36}' \
  | tail -n 1)" || true

if [[ -z "${udid}" ]]; then
  echo "error: no tvOS simulator is available." >&2
  echo "       Install one with: xcodebuild -downloadPlatform tvOS" >&2
  exit 1
fi

echo "platform=tvOS Simulator,id=${udid}"
