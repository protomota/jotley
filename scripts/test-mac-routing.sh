#!/bin/zsh
# Uses the actual Debug app module and an existing Swift test source.
set -euo pipefail
task_repo_root="$(cd "$(dirname "$0")/.." && pwd)"
task_products="${JOTLEY_MAC_BUILD_PRODUCTS:-/tmp/jotley-local-xcode-build/Build/Products/Debug}"
task_app_source="$task_products/Jotley.app/Contents"
test -f "$task_app_source/MacOS/Jotley.debug.dylib"
test -d "$task_app_source/Resources/JotleyNotes.momd"
task_harness_root="$(mktemp -d /tmp/jotley-mac-routing.XXXXXX)"
task_profile_file="$HOME/Library/Containers/com.protomota.jotley.mac-routing-tests/Data/tmp/routing-$$.profraw"
trap 'rm -rf "$task_harness_root"; rm -f "$task_profile_file"' EXIT
task_harness_app="$task_harness_root/JotleyRoutingTests.app"
mkdir -p "$task_harness_app/Contents/MacOS" "$task_harness_app/Contents/Resources" "$task_harness_app/Contents/Frameworks"
cp -R "$task_app_source/Resources/JotleyNotes.momd" "$task_harness_app/Contents/Resources/"
cp "$task_app_source/MacOS/Jotley.debug.dylib" "$task_harness_app/Contents/MacOS/"
cp -R "$task_app_source/Frameworks/Sparkle.framework" "$task_harness_app/Contents/Frameworks/"
python3 - "$task_harness_app/Contents/Info.plist" "$task_harness_root/entitlements.plist" <<'PY'
import plistlib, sys
info = {
    'CFBundleIdentifier': 'com.protomota.jotley.mac-routing-tests',
    'CFBundleExecutable': 'MacRoutingHarness',
    'CFBundleName': 'Jotley Routing Tests',
    'CFBundlePackageType': 'APPL',
    'LSMinimumSystemVersion': '27.0',
    'LSUIElement': True,
    'NSMicrophoneUsageDescription': 'Routing regression tests must not begin microphone capture.',
}
for path, data in [(sys.argv[1], info), (sys.argv[2], {'com.apple.security.app-sandbox': True})]:
    with open(path, 'wb') as output: plistlib.dump(data, output)
PY
task_arch="$(uname -m)"
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -parse-as-library -D JOTLEY_MAC_ROUTING_HARNESS \
  -target "$task_arch-apple-macos27.0" -sdk "$task_sdk" \
  -I "$task_products" -F "$task_products" "$task_repo_root/JotleyUITests-macOS/JotleyUITests_macOS.swift" \
  "$task_harness_app/Contents/MacOS/Jotley.debug.dylib" \
  -Xlinker -rpath -Xlinker @executable_path \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$task_harness_app/Contents/MacOS/MacRoutingHarness"
codesign --force --sign - "$task_harness_app/Contents/MacOS/Jotley.debug.dylib"
# The separate test identity has App Sandbox and no audio/network entitlements.
# It never changes the production app's signature, entitlements or permissions.
codesign --force --sign - --entitlements "$task_harness_root/entitlements.plist" "$task_harness_app"
LLVM_PROFILE_FILE="$task_profile_file" "$task_harness_app/Contents/MacOS/MacRoutingHarness" "$@"
