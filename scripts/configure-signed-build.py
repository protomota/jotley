#!/usr/bin/env python3
"""Prepare private signing configuration; never provision, archive or upload an app."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=["macos", "ios"])
    parser.add_argument("--team", required=True, help="Apple developer team identifier")
    parser.add_argument("--container", required=True, help="Provisioned CloudKit container")
    parser.add_argument("--environment", choices=["development", "production"], default="development")
    parser.add_argument("--signing-style", choices=["Automatic", "Manual"], default="Automatic")
    parser.add_argument("--bundle-id", default="com.protomota.jotley", help="Existing Jotley listing identity; forks must use their own")
    parser.add_argument("--build-number", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        parser.error("Team must be a ten-character Apple developer team identifier.")
    if not re.fullmatch(r"iCloud\.[A-Za-z0-9.-]+", args.container):
        parser.error("Container must start with iCloud. and contain only identifier characters.")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("Invalid bundle identifier.")
    if args.build_number < 1:
        parser.error("Build number must be positive and newer than the listing's existing builds.")
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
    entitlements.update({"com.apple.developer.icloud-container-identifiers": [args.container],
                         "com.apple.developer.icloud-services": ["CloudKit"],
                         "com.apple.developer.icloud-container-environment": args.environment.capitalize(),
                         "com.apple.developer.aps-environment" if args.platform == "macos" else "aps-environment": args.environment})
    if args.platform == "macos":
        entitlements["com.apple.security.network.client"] = True
        info["SUEnableDownloaderService"] = False
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
    identity = "Apple Development" if args.environment == "development" else "Apple Distribution"
    config = f'''// Private build configuration. Generated files must not be committed.
DEVELOPMENT_TEAM = {args.team}
PRODUCT_BUNDLE_IDENTIFIER = {args.bundle_id}
MARKETING_VERSION = 2.0
CURRENT_PROJECT_VERSION = {args.build_number}
CODE_SIGN_STYLE = {args.signing_style}
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
        config += "ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES\n"
    paths[2].write_text(config)
    os.chmod(paths[2], 0o600)
    print(paths[2])


if __name__ == "__main__":
    main()
