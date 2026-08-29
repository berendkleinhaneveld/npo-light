#!/usr/bin/env bash
#
# Installs the latest SwiftLint release on Linux, for linting without a Mac.
#
# The release ships a statically linked binary that needs no Swift toolchain.
# It runs every rule except the handful that need SourceKit, which it names on
# stderr as it skips them -- CI on macOS remains the authority.
#
# Usage:  ./scripts/install-swiftlint-linux.sh [install-dir]   (default: ~/.local/bin)

set -euo pipefail

install_dir="${1:-${HOME}/.local/bin}"

case "$(uname -m)" in
  x86_64|amd64) asset="swiftlint_linux_amd64.zip" ;;
  aarch64|arm64) asset="swiftlint_linux_arm64.zip" ;;
  *)
    echo "error: no SwiftLint Linux build for $(uname -m)." >&2
    exit 1
    ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

url="https://github.com/realm/SwiftLint/releases/latest/download/${asset}"
echo "Downloading ${url}" >&2
curl -sSL -o "${tmp}/swiftlint.zip" "${url}"

if command -v unzip >/dev/null 2>&1; then
  unzip -o -q "${tmp}/swiftlint.zip" -d "${tmp}/swiftlint"
else
  python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
    "${tmp}/swiftlint.zip" "${tmp}/swiftlint"
fi

mkdir -p "${install_dir}"
install -m 0755 "${tmp}/swiftlint/swiftlint-static" "${install_dir}/swiftlint-static"

echo "Installed $("${install_dir}/swiftlint-static" version) to ${install_dir}/swiftlint-static" >&2
echo "Add it to your PATH, then run ./scripts/lint.sh" >&2
