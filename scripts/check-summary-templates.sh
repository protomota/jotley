#!/bin/zsh
# Generates a real on-device summary with every template and checks the
# structured rendering. Needs Apple Intelligence on this Mac and a Debug build.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
products="${JOTLEY_MAC_BUILD_PRODUCTS:-/tmp/jotley-local-xcode-build/Build/Products/Debug}"
work="$(mktemp -d /tmp/jotley-summary-templates.XXXXXX)"
cp "$products/Jotley.app/Contents/MacOS/Jotley.debug.dylib" "$work/"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos27.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -I "$products" -F "$products" "$repo_root/scripts/summary-template-check.swift" "$work/Jotley.debug.dylib" \
  -Xlinker -rpath -Xlinker @executable_path -Xlinker -rpath -Xlinker "$products" -o "$work/summary-template-check"
cd "$work" && ./summary-template-check "$@"
echo "Results and renders: $work"
