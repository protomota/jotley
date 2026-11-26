#!/bin/zsh
set -euo pipefail
task_repo_root="$(cd "$(dirname "$0")/.." && pwd)"
task_products="${JOTLEY_MAC_BUILD_PRODUCTS:?Set JOTLEY_MAC_BUILD_PRODUCTS to the Debug build products directory.}"
task_output="${JOTLEY_MCP_TEST_OUTPUT:?Set JOTLEY_MCP_TEST_OUTPUT to an output directory on Expand.}"
task_name=JotleyMCPTests
task_sources=( "$task_repo_root/scripts/mcp-integration.swift" )
task_flags=()
if [[ "${1:-}" == --demo ]]; then
    shift
    task_name=JotleyMCPDemo
    task_sources+=( "$task_repo_root/scripts/mcp-demo.swift" )
    task_flags+=( -D JOTLEY_MCP_DEMO )
fi
task_contents="$task_output/$task_name.app/Contents"
mkdir -p "$task_contents/MacOS" "$task_contents/Resources" "$task_contents/Frameworks"
cp -R "$task_products/Jotley.app/Contents/Resources/." "$task_contents/Resources/"
cp "$task_repo_root/scripts/mcp-desktop-bridge-check.cjs" "$task_contents/Resources/"
if [[ -n "${JOTLEY_NODE_BINARY:-}" ]]; then
    # A self-contained test runtime lives inside the harness so its sandbox does
    # not need access to a user's Node installation or package-manager folders.
    cp "$JOTLEY_NODE_BINARY" "$task_contents/MacOS/node"
    codesign --force --sign - "$task_contents/MacOS/node"
    export JOTLEY_NODE_BINARY="$task_contents/MacOS/node"
fi
cp "$task_products/Jotley.app/Contents/MacOS/Jotley.debug.dylib" "$task_contents/MacOS/"
cp "$task_products/Jotley.app/Contents/MacOS/Jotley" "$task_contents/MacOS/JotleyBridge"
codesign --force --sign - "$task_contents/MacOS/JotleyBridge"
cp -R "$task_products/Jotley.app/Contents/Frameworks/Sparkle.framework" "$task_contents/Frameworks/"
cat > "$task_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.protomota.jotley.mcp-tests</string>
<key>CFBundleExecutable</key><string>MCPIntegration</string>
<key>CFBundleName</key><string>Jotley MCP Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cat > "$task_output/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.server</key><true/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
task_checkouts="${JOTLEY_MCP_PACKAGE_CHECKOUTS:-$task_products/../../../SourcePackages/checkouts}"
task_modules=( -I "$task_products" -F "$task_products" )
for task_module_map in "$task_checkouts"/*/Sources/*/include/module.modulemap(N); do
    task_modules+=( -Xcc "-fmodule-map-file=$task_module_map" -Xcc "-I${task_module_map:h}" )
done
for task_module_map in "$task_products/../../Intermediates.noindex/GeneratedModuleMaps/"*.modulemap(N); do
    task_modules+=( -Xcc "-fmodule-map-file=$task_module_map" )
done
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos27.0" \
  "${task_modules[@]}" "${task_flags[@]}" "${task_sources[@]}" \
  "$task_contents/MacOS/Jotley.debug.dylib" \
  -Xlinker -rpath -Xlinker @executable_path \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$task_contents/MacOS/MCPIntegration"
codesign --force --sign - "$task_contents/MacOS/Jotley.debug.dylib"
if [[ "$task_name" == JotleyMCPDemo ]]; then
    # The view recorder writes directly to the requested Expand output. It uses
    # an in-memory fixture and never opens the installed app's preferences/store.
    plutil -replace CFBundleIdentifier -string com.protomota.jotley.mcp-demo "$task_contents/Info.plist"
    codesign --force --sign - "$task_output/$task_name.app"
else
    codesign --force --sign - --entitlements "$task_output/entitlements.plist" "$task_output/$task_name.app"
fi
LLVM_PROFILE_FILE=/dev/null "$task_contents/MacOS/MCPIntegration" "$@"
