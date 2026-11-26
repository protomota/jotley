#!/usr/bin/env python3
"""Prepare private signing configuration; never provision, archive or upload an app."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
from signing_identity import KINDS, local_signing_identity


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=["macos", "ios"])
    parser.add_argument("--team", required=True, help="Apple developer team identifier")
    parser.add_argument("--container", required=True, help="Provisioned CloudKit container")
    parser.add_argument("--environment", choices=["development", "production"], default="development")
    parser.add_argument("--signing-style", choices=["Automatic", "Manual"], help="Defaults to Manual for local Mac builds, Automatic for iOS")
    parser.add_argument("--mac-signing-kind", choices=KINDS, help="Local Mac certificate type; production defaults to Developer ID for website distribution")
    parser.add_argument("--signing-identity", help="Exact local Mac certificate name or SHA-1; selected only from login")
    parser.add_argument("--mac-profile", help="Existing Mac provisioning profile name, applied only to the app target")
    parser.add_argument("--isolated-local-test", action="store_true", help="Use a separate Mac test library and disable iCloud sync and updates")
    parser.add_argument("--bundle-id", default="com.protomota.jotley", help="Existing Jotley listing identity; forks must use their own")
    parser.add_argument("--build-number", required=True, type=int)
    parser.add_argument("--version", default="2.3.0", help="Marketing version for this build")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    signing_style = args.signing_style or ("Manual" if args.platform == "macos" else "Automatic")
    if args.platform != "macos" and (args.mac_signing_kind or args.signing_identity or args.mac_profile):
        parser.error("Mac signing options cannot be used for iOS. iOS uses Apple Development or Apple Distribution.")
    if args.isolated_local_test and (args.platform != "macos" or args.environment != "development" or args.mac_signing_kind not in (None, "development")):
        parser.error("An isolated local test requires a Mac development build.")
    if args.mac_profile and any(c in args.mac_profile for c in ['\n', '\r', '"', '$']):
        parser.error("Profile name contains unsupported xcconfig characters.")
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        parser.error("Team must be a ten-character Apple developer team identifier.")
    if not re.fullmatch(r"iCloud\.[A-Za-z0-9.-]+", args.container):
        parser.error("Container must start with iCloud. and contain only identifier characters.")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("Invalid bundle identifier.")
    if args.build_number < 1:
        parser.error("Build number must be positive and newer than the listing's existing builds.")
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", args.version):
        parser.error("Version must contain two or three numeric components.")
    identity = "Apple Development" if args.environment == "development" else "Apple Distribution"
    if args.platform == "macos":
        kind = args.mac_signing_kind or ("development" if args.environment == "development" else "developer-id")
        if signing_style == "Automatic" and (kind != "development" or args.mac_profile):
            parser.error("Automatic Mac signing uses an installed Xcode-managed development profile. Use Manual for an explicit profile or distribution identity.")
        try:
            identity = local_signing_identity(args.signing_identity or KINDS[kind], kind)
        except ValueError as error:
            parser.error(str(error))
        if signing_style == "Automatic":
            identity = KINDS[kind]
    repo = Path(__file__).resolve().parent.parent
    output = args.output.expanduser().resolve()
    if any(c in str(output) for c in ['\n', '\r', '"', '$']):
        parser.error("Output path contains unsupported xcconfig characters.")
    if output.is_relative_to(repo):
        relative = output.relative_to(repo)
        if subprocess.run(["git", "check-ignore", "-q", "--", str(relative)], cwd=repo).returncode:
            parser.error("Signing configuration inside the checkout must be git-ignored (use .private-release/).")
    paths = [output / name for name in ["Info.plist", "Jotley.entitlements", "Signing.xcconfig"]]
    widget_paths = [output / name for name in ["Widget-Info.plist", "Widget.entitlements"]] if args.platform == "ios" else []
    if any(path.exists() for path in paths + widget_paths):
        parser.error("Output already contains configuration; use a fresh directory to avoid overwriting it.")
    source = repo / ("macOS" if args.platform == "macos" else "iOS")
    with (source / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    info.update(CFBundleDisplayName="Jotley", CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)",
                CFBundleShortVersionString="$(MARKETING_VERSION)", CFBundleVersion="$(CURRENT_PROJECT_VERSION)",
                JotleyCloudKitContainerIdentifier=args.container, ITSAppUsesNonExemptEncryption=False)
    if args.platform == "ios":
        info["UIBackgroundModes"] = list(dict.fromkeys(info.get("UIBackgroundModes", []) + ["remote-notification"]))
    with (source / "Jotley.entitlements").open("rb") as handle:
        entitlements = plistlib.load(handle)
    if args.platform == "macos" and kind == "developer-id" and entitlements.get("com.apple.developer.applesignin"):
        parser.error("Developer ID does not support native Sign in with Apple. Use a development build for local testing; website distribution needs browser-based sign-in before signing.")
    entitlements.update({"com.apple.developer.icloud-container-identifiers": [args.container],
                         "com.apple.developer.ubiquity-kvstore-identifier": args.team + "." + args.bundle_id,
                         "com.apple.developer.icloud-services": ["CloudKit"],
                         "com.apple.developer.icloud-container-environment": args.environment.capitalize(),
                         "com.apple.developer.aps-environment" if args.platform == "macos" else "aps-environment": args.environment})
    if args.platform == "macos":
        entitlements["com.apple.security.network.client"] = True
        # These entitlements are also passed directly to codesign during packaging.
        # Only Xcode expands build settings in an entitlements file.
        installer_lookup = "com.apple.security.temporary-exception.mach-lookup.global-name"
        if installer_lookup in entitlements:
            entitlements[installer_lookup] = [
                service.replace("$(PRODUCT_BUNDLE_IDENTIFIER)", args.bundle_id)
                for service in entitlements[installer_lookup]
            ]
        info["SUEnableDownloaderService"] = False
        if kind == "developer-id" and args.environment == "production":
            info["JotleyEnableSparkle"] = True
        if args.isolated_local_test:
            info.update(CFBundleDisplayName="Jotley Test", CFBundleName="Jotley Test",
                        JotleyIsolatedLocalTest=True, JotleyEnableSparkle=False)
            info.pop("JotleyCloudKitContainerIdentifier", None)
            for key in ["com.apple.developer.icloud-container-identifiers", "com.apple.developer.ubiquity-kvstore-identifier",
                        "com.apple.developer.icloud-services", "com.apple.developer.icloud-container-environment",
                        "com.apple.developer.aps-environment"]:
                entitlements.pop(key, None)
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    for path, value in zip(paths[:2], [info, entitlements]):
        with path.open("wb") as handle:
            plistlib.dump(value, handle)
        os.chmod(path, 0o600)
    if widget_paths:
        widget_info = plistlib.loads((repo / "JotleyWidgets" / "Info.plist").read_bytes())
        widget_info.update(CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)",
                           CFBundleShortVersionString="$(MARKETING_VERSION)",
                           CFBundleVersion="$(CURRENT_PROJECT_VERSION)")
        for path, value in zip(widget_paths, [widget_info, {}]):
            path.write_bytes(plistlib.dumps(value)); os.chmod(path, 0o600)
    config = f'''// Private build configuration. Generated files must not be committed.
DEVELOPMENT_TEAM = {args.team}
PRODUCT_BUNDLE_IDENTIFIER = {args.bundle_id}
MARKETING_VERSION = {args.version}
CURRENT_PROJECT_VERSION = {args.build_number}
CODE_SIGN_STYLE = {signing_style}
CODE_SIGN_IDENTITY = {identity}
CODE_SIGN_ENTITLEMENTS = {paths[1]}
INFOPLIST_FILE = {paths[0]}
'''
    if args.platform == "ios":
        # -xcconfig applies to every archive target. Resolve target-specific
        # settings so the extension never receives the app's identity/profile,
        # CloudKit entitlements or application Info.plist.
        config += f'''TARGETED_DEVICE_FAMILY = 1,2
JOTLEY_TARGET_KEY = $(TARGET_NAME:c99extidentifier)
JOTLEY_BUNDLE_Jotley_iOS = {args.bundle_id}
JOTLEY_BUNDLE_JotleyWidgetsExtension = {args.bundle_id}.JotleyWidgets
JOTLEY_INFO_Jotley_iOS = {paths[0]}
JOTLEY_INFO_JotleyWidgetsExtension = {widget_paths[0]}
JOTLEY_MICROPHONE_Jotley_iOS = Jotley uses your microphone for live, on-device transcription. No audio files are saved.
INFOPLIST_KEY_NSMicrophoneUsageDescription = $(JOTLEY_MICROPHONE_$(JOTLEY_TARGET_KEY))
JOTLEY_ENTITLEMENTS_Jotley_iOS = {paths[1]}
JOTLEY_ENTITLEMENTS_JotleyWidgetsExtension = {widget_paths[1]}
PRODUCT_BUNDLE_IDENTIFIER = $(JOTLEY_BUNDLE_$(JOTLEY_TARGET_KEY))
INFOPLIST_FILE = $(JOTLEY_INFO_$(JOTLEY_TARGET_KEY))
CODE_SIGN_ENTITLEMENTS = $(JOTLEY_ENTITLEMENTS_$(JOTLEY_TARGET_KEY))
PROVISIONING_PROFILE_SPECIFIER = $(JOTLEY_PROFILE_$(JOTLEY_TARGET_KEY))
'''
    else:
        # An override xcconfig also reaches SwiftPM resource bundles. Keep the
        # app's identity, profile and entitlements off the NIO resource target.
        config += f'''JOTLEY_TARGET_KEY = $(TARGET_NAME:c99extidentifier)
JOTLEY_BUNDLE_Jotley = {args.bundle_id}
JOTLEY_BUNDLE_swift_nio_NIOPosix = swift-nio.NIOPosix.resources
JOTLEY_INFO_Jotley = {paths[0]}
JOTLEY_ENTITLEMENTS_Jotley = {paths[1]}
JOTLEY_IDENTITY_Jotley = {identity}
JOTLEY_IDENTITY_swift_nio_NIOPosix = -
JOTLEY_PROFILE_Jotley = {args.mac_profile or ""}
PRODUCT_BUNDLE_IDENTIFIER = $(JOTLEY_BUNDLE_$(JOTLEY_TARGET_KEY))
INFOPLIST_FILE = $(JOTLEY_INFO_$(JOTLEY_TARGET_KEY))
CODE_SIGN_ENTITLEMENTS = $(JOTLEY_ENTITLEMENTS_$(JOTLEY_TARGET_KEY))
CODE_SIGN_IDENTITY = $(JOTLEY_IDENTITY_$(JOTLEY_TARGET_KEY))
PROVISIONING_PROFILE_SPECIFIER = $(JOTLEY_PROFILE_$(JOTLEY_TARGET_KEY))
ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES
'''
        config += f'OTHER_CODE_SIGN_FLAGS = $(inherited) --keychain "{Path.home() / "Library/Keychains/login.keychain-db"}"\n'
    paths[2].write_text(config)
    os.chmod(paths[2], 0o600)
    print(paths[2])


if __name__ == "__main__":
    main()
