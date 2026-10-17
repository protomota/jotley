# Build Jotley locally

Use Xcode 27 on macOS 27. The source contains the Mac app, a universal iPhone/iPad app and the widget/Live Activity extension. Local development identities use their own storage and do not enable the official app's private CloudKit container.

```sh
git clone https://github.com/protomota/jotley.git
cd jotley
open Jotley.xcodeproj
```

Select **Jotley** for Mac or **Jotley-iOS** for iPhone/iPad, choose a destination, then Run. Apple Intelligence hardware and ready Apple models are required for actual generation/transcription. Simulator availability varies; a successful UI test is not proof of physical speech recognition or locked-device behavior.

## Command-line builds

```sh
# Local Mac build, with an ad-hoc development signature.
xcodebuild -project Jotley.xcodeproj -scheme Jotley -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/jotley-mac-build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

# Unsigned iPhone/iPad simulator build.
xcodebuild -project Jotley.xcodeproj -scheme Jotley-iOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/jotley-ios-build CODE_SIGNING_ALLOWED=NO build
```

The pinned Sparkle dependency is resolved by Xcode. Resolving build dependencies may need internet access; this is separate from the app's on-device processing.

## Checks

```sh
swift test --scratch-path /tmp/jotley-shared-tests

JOTLEY_MAC_BUILD_PRODUCTS=/tmp/jotley-mac-build/Build/Products/Debug \
  zsh scripts/test-mac-routing.sh
JOTLEY_MAC_BUILD_PRODUCTS=/tmp/jotley-mac-build/Build/Products/Debug \
  zsh scripts/test-mac-routing.sh --summary-scroll-only

# Real Apple model: every summary template renders as a structured summary.
JOTLEY_MAC_BUILD_PRODUCTS=/tmp/jotley-mac-build/Build/Products/Debug \
  zsh scripts/check-summary-templates.sh
```

The Mac harness uses a separate sandboxed identity and does not change the official app's recording permissions. For mobile tests, select your installed iPhone/iPad simulator in Xcode and run the Jotley-iOSTests and Jotley-iOSUITests targets. Actual model checks explicitly skip if Apple does not expose a usable model; deterministic UI fixtures are not recognition tests.

## Your own device signing and iCloud

For a physical iPhone/iPad, select your own Apple development team in Xcode's Signing & Capabilities, and use identifiers/profiles owned by that team. Public source includes no certificates, private keys, provisioning profiles or official release credentials.

Optional iCloud requires your own app identifiers, CloudKit container, capabilities and matching profiles. Register them in [Apple Developer — Identifiers](https://developer.apple.com/account/resources/identifiers/list), then follow [Apple's Core Data with CloudKit setup](https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit). The helper `scripts/configure-signed-build.py --help` describes generating local configuration without editing the project file. Keep generated `.private-release/` contents out of Git.

The official App Store/TestFlight and notarized Mac release pipelines stay in the private maintainer repository. They are not needed to compile this public source. Sparkle remains disabled for the isolated development identities.
