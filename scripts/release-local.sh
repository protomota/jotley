#!/bin/zsh
set -euo pipefail

usage() {
    print -u2 'Usage: zsh scripts/release-local.sh {ios|mac} BUILD SIGNING_XCCONFIG OUTPUT_DIR [IOS_EXPORT_OPTIONS]'
    exit 2
}
if (( $# < 4 || $# > 5 )) || [[ "$1" != (ios|mac) || "$2" != <1-> ]]; then usage; fi

platform="$1"
build="$2"
config="${3:A}"
output="${4:A}"
repo="${0:A:h:h}"
if [[ "$output" != /Volumes/Expand/* || ! -d /Volumes/Expand || ! -r "$config" || -e "$output" ]]; then
    print -u2 'Use an existing signing config and a fresh output directory on the mounted Expand drive.'
    exit 2
fi
if [[ "$platform" == ios ]]; then
    if (( $# != 5 )) || [[ ! -r "$5" ]]; then usage; fi
else
    if (( $# != 4 )); then usage; fi
fi
mkdir -p "$output/tmp"
export TMPDIR="$output/tmp"
args=(-project "$repo/Jotley.xcodeproj" -configuration Release -xcconfig "$config"
      -derivedDataPath "${JOTLEY_DERIVED_DATA:-$output/DerivedData}")
if [[ -n "${JOTLEY_PACKAGES_PATH:-}" ]]; then
    args+=(-clonedSourcePackagesDirPath "$JOTLEY_PACKAGES_PATH" -disableAutomaticPackageResolution)
fi

if [[ "$platform" == ios ]]; then
    archive="$output/Jotley-iOS.xcarchive"
    xcodebuild "${args[@]}" -scheme Jotley-iOS -destination generic/platform=iOS -archivePath "$archive" archive
    app="$archive/Products/Applications/Jotley-iOS.app"
    [[ "$(plutil -extract CFBundleVersion raw -o - "$app/Info.plist")" == "$build" ]]
    codesign --verify --deep --strict "$app"
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$output/export" -exportOptionsPlist "${5:A}"
    print -r -- "TestFlight archive: $output/export/Jotley-iOS.ipa"
    exit
fi

products="$output/products"
xcodebuild "${args[@]}" -scheme Jotley -destination 'platform=macOS,arch=arm64' CONFIGURATION_BUILD_DIR="$products" build
app="$output/Jotley.app"
ditto "$products/Jotley.app" "$app"
info="$app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleVersion raw -o - "$info")" == "$build" ]]
version="$(plutil -extract CFBundleShortVersionString raw -o - "$info")"
codesign --display --entitlements :- "$app" > "$output/app-entitlements.plist"
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$output/app-entitlements.plist" >/dev/null 2>&1; then
    print -u2 'Distribution cannot use an app signed with get-task-allow.'
    exit 1
fi
identity="${JOTLEY_MAC_RELEASE_IDENTITY:?Set the existing Developer ID Application certificate name or SHA-1.}"
identity="$(python3 "$repo/scripts/signing_identity.py" "$identity" --kind developer-id)"
keychain="$HOME/Library/Keychains/login.keychain-db"
sign() { codesign --force --sign "$identity" --keychain "$keychain" --options runtime --timestamp "$@"; }
cp "$repo/packaging/macos/background.tiff" "$app/Contents/Resources/JotleyInstallerBackground.tiff"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
for component in Autoupdate Updater.app XPCServices/Downloader.xpc XPCServices/Installer.xpc; do
    sign "$sparkle/Versions/B/$component"
done
sign "$sparkle"
sign --entitlements "$output/app-entitlements.plist" "$app"
codesign --verify --deep --strict "$app"
zip="$output/Jotley-$version-$build-app.zip"
dmg="$output/Jotley-$version-$build.dmg"
ditto -c -k --keepParent "$app" "$zip"
python3 "$repo/scripts/release-local-delivery.py" notarize "$zip" "$output/app-notarization.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
packaging_python="${JOTLEY_PACKAGING_PYTHON:-python3}"
"$packaging_python" "$repo/scripts/package-mac-dmg.py" --app "$app" --output "$dmg"
codesign --force --sign "$identity" --keychain "$keychain" --timestamp "$dmg"
python3 "$repo/scripts/release-local-delivery.py" notarize "$dmg" "$output/dmg-notarization.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"
"$packaging_python" "$repo/scripts/package-mac-dmg.py" --app "$app" --output "$dmg" --verify-only
shasum -a 256 "$dmg"
print -r -- "Notarized Mac installer: $dmg"
