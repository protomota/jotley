#!/usr/bin/env python3
"""Verify model linkage and the exported iOS summary background configuration."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile


def check(binary):
    symbols = subprocess.check_output(["xcrun", "nm", "-u", str(binary)], text=True)
    missing_api = [line.strip() for line in symbols.splitlines()
                   if "FoundationModels19SystemLanguageModelC7VariantV" in line
                   or "FoundationModels19SystemLanguageModelC7variant" in line]
    if missing_api:
        raise SystemExit("Incompatible Foundation Models variant imports: " + "; ".join(missing_api))
    print("Verified: no incompatible Foundation Models model-variant imports.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, help="App executable or exported IPA")
    artifact = parser.parse_args().artifact
    if artifact.suffix.lower() != ".ipa":
        check(artifact)
        return
    with zipfile.ZipFile(artifact) as archive, tempfile.TemporaryDirectory() as directory:
        infos = [name for name in archive.namelist()
                 if name.startswith("Payload/") and name.endswith(".app/Info.plist") and name.count("/") == 2]
        if len(infos) != 1:
            raise SystemExit("Expected one main app in the IPA.")
        info = plistlib.loads(archive.read(infos[0]))
        identifiers = info.get("BGTaskSchedulerPermittedIdentifiers", [])
        if any(".summary." in item for item in identifiers):
            expected = info["CFBundleIdentifier"] + ".summary.*"
            if expected not in identifiers or "processing" not in info.get("UIBackgroundModes", []):
                raise SystemExit("Exported summary background processing registration or mode is missing.")
            print("Verified: exported summary background identifier and processing mode.")
        executable = info["CFBundleExecutable"]
        if Path(executable).name != executable:
            raise SystemExit("Invalid app executable name.")
        binary = Path(directory) / executable
        binary.write_bytes(archive.read(infos[0].rsplit("/", 1)[0] + "/" + executable))
        check(binary)


if __name__ == "__main__":
    main()
