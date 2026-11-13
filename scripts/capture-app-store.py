#!/usr/bin/env python3
"""Capture Jotley's localized storefront images with Xcode UI tests."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
EXPAND = Path("/Volumes/Expand")
STORE_LOCALES = {
    "en": "en-US", "da": "da", "nl": "nl-NL", "fr": "fr-FR", "de": "de-DE",
    "it": "it", "nb": "no", "pt-BR": "pt-BR", "es": "es-ES", "sv": "sv",
    "tr": "tr", "vi": "vi", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
    "ja": "ja", "ko": "ko",
}
DEVICES = {
    "iphone": ("iPhone 17 Pro", (1206, 2622)),
    "iphone-large": ("iPhone 17 Pro Max", (1320, 2868)),
    "ipad": ("iPad Pro 13-inch", (2064, 2752)),
    "mac": ("Mac", (1440, 900)),
}
MOBILE_SCENES = ("01-library", "02-summary", "03-transcript")
LARGE_SCREEN_SCENES = ("01-summary", "02-transcript", "03-folders")


def fixtures() -> dict[str, dict[str, str]]:
    catalog = json.loads((ROOT / "Shared/Localizable.xcstrings").read_text())["strings"]
    results = {}
    for row in (ROOT / "scripts/app-store-screenshot-fixtures.txt").read_text().splitlines():
        locale, country, title, *fields = row.split("|")
        design, weekly, feedback, folder, launch, design_tag, first, second, summary, task1, task2 = fields

        def label(key: str) -> str:
            if locale == "en":
                return key
            return catalog[key]["localizations"][locale]["stringUnit"]["value"]

        notes = [
            {
                "title": title, "folder": folder, "tags": [launch, design_tag],
                "transcript": f"{first}\n\n{second}",
                "summary": f"{summary}\n\n- {task1}\n- {task2}",
            },
            *(
                {"title": name, "folder": folder, "tags": [], "transcript": body, "summary": ""}
                for name, body in ((design, second), (weekly, summary), (feedback, first))
            ),
        ]
        results[locale] = {
            "notes": json.dumps(notes, ensure_ascii=False),
            "region": f"{('pt' if locale == 'pt-BR' else locale.replace('-', '_'))}_{country}",
            "title": title,
            "libraryLabel": label("Notes"),
            "transcriptLabel": label("Transcript"),
            "foldersLabel": label("Folders"),
        }
    if results.keys() != STORE_LOCALES.keys():
        raise ValueError("The screenshot fixtures must cover all storefront localizations.")
    return results


def run(command: list[str], log: Path, env: dict[str, str]) -> None:
    print(f"{command[0]} {command[1]} → {log}", flush=True)
    with log.open("w") as output:
        subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, check=True)


def capture(args: argparse.Namespace, samples: dict[str, dict[str, str]]) -> None:
    if not EXPAND.is_mount():
        raise SystemExit("Mount the Expand drive before capturing screenshots.")
    output = args.output.expanduser().resolve()
    if not output.is_relative_to(EXPAND):
        raise SystemExit("Choose an output directory on /Volumes/Expand.")
    output.mkdir(parents=True, exist_ok=False)
    temp = output / "tmp"
    temp.mkdir()
    env = {**os.environ, "TMPDIR": str(temp)}
    mac = args.device == "mac"
    target = "JotleyUITests-macOS/JotleyLocalUITests" if mac else "Jotley-iOSUITests/Jotley_iOSUITests"
    destination = "platform=macOS,arch=arm64" if mac else f"platform=iOS Simulator,id={args.udid}"
    if not mac:
        subprocess.run(
            ["xcrun", "simctl", "status_bar", args.udid, "override", "--time", "9:41",
             "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
             "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "discharging",
             "--batteryLevel", "100"],
            env=env, check=True,
        )
    if args.xctestrun:
        source_run = args.xctestrun.resolve()
    else:
        products = output / "build"
        settings = ["CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=",
                    "CODE_SIGN_ENTITLEMENTS="] if mac else ["CODE_SIGNING_ALLOWED=NO"]
        command = [
            "xcodebuild", "-project", "Jotley.xcodeproj", "-scheme", "Jotley" if mac else "Jotley-iOS",
            "-configuration", "Debug", "-destination", destination,
            "-derivedDataPath", str(products), "-jobs", "6",
        ]
        if args.packages:
            command += ["-clonedSourcePackagesDirPath", str(args.packages), "-disableAutomaticPackageResolution"]
        run([*command, *settings, "build-for-testing"], output / "build.log", env)
        source_run, = (products / "Build/Products").glob("*.xctestrun")

    config = plistlib.loads(source_run.read_bytes())
    test_targets = [entry for group in config["TestConfigurations"] for entry in group["TestTargets"]
                    if entry["BlueprintName"] == target.split("/")[0]]
    if not test_targets:
        raise ValueError(f"{source_run} does not contain {target}.")
    for entry in test_targets:
        entry.setdefault("EnvironmentVariables", {})["JOTLEY_STORE_SCREENSHOT_FIXTURE"] = json.dumps(samples)
    # Xcode resolves __TESTROOT__ relative to the xctestrun file.
    run_path = source_run.with_name(f"{source_run.stem}-store-{os.getpid()}.xctestrun")
    with run_path.open("xb") as file:
        plistlib.dump(config, file)
    result = output / "capture.xcresult"
    try:
        run(
            ["xcodebuild", "test-without-building", "-xctestrun", str(run_path), "-destination",
             destination, "-parallel-testing-enabled", "NO",
             f"-only-testing:{target}/testLocalizedStorefrontCaptures", "-resultBundlePath", str(result)],
            output / "capture.log", env,
        )
    finally:
        run_path.unlink()
    export(result, output, args.device, samples, env)


def export(result: Path, output: Path, device: str, samples: dict[str, dict[str, str]],
           env: dict[str, str]) -> None:
    raw = output / "attachments"
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                    "--output-path", str(raw)], env=env, check=True)
    scenes = LARGE_SCREEN_SCENES if device in {"mac", "ipad"} else MOBILE_SCENES
    pattern = re.compile(r"^JotleyStore-(.+?)-(" + "|".join(map(re.escape, scenes)) + r")(?=[_.]|$)")
    manifest = json.loads((raw / "manifest.json").read_text())
    actual = {}
    for test in manifest:
        for attachment in test["attachments"]:
            if match := pattern.match(attachment["suggestedHumanReadableName"].removesuffix(".png")):
                key = tuple(match.groups())
                if key in actual:
                    raise ValueError(f"Duplicate capture {key}")
                actual[key] = raw / attachment["exportedFileName"]
    expected = {(locale, scene) for locale in samples for scene in scenes}
    if actual.keys() != expected:
        raise ValueError(f"Capture mismatch. Missing {expected - actual.keys()}. Extra {actual.keys() - expected}.")
    for locale in samples:
        checksums = {hashlib.sha256(actual[(locale, scene)].read_bytes()).digest() for scene in scenes}
        if len(checksums) != len(scenes):
            raise ValueError(f"{locale} contains identical screenshots for different scenes.")
    width, height = DEVICES[device][1]
    for (locale, scene), source in sorted(actual.items()):
        dimensions = subprocess.check_output(["magick", "identify", "-format", "%w %h", str(source)], env=env, text=True)
        if device != "mac" and dimensions != f"{width} {height}":
            raise ValueError(f"{locale} {scene} is {dimensions}, expected {width} {height}.")
        destination = output / "store" / STORE_LOCALES[locale] / f"{device}-{scene}.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        convert = ["magick", str(source), "-background", "#f6f6f6", "-alpha", "remove", "-alpha", "off"]
        if device == "mac":
            capture_width, capture_height = map(int, dimensions.split())
            if abs(capture_width / capture_height - 3 / 2) > 0.01:
                raise ValueError(f"{locale} {scene} has a non-3:2 Mac window: {dimensions}.")
            native = output / "mac-3x2" / STORE_LOCALES[locale] / destination.name
            native.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run([*convert, f"PNG24:{native}"], env=env, check=True)
            convert += ["-resize", f"{width}x{height}", "-gravity", "center", "-extent", f"{width}x{height}"]
        subprocess.run([*convert, f"PNG24:{destination}"], env=env, check=True)
    print(f"Exported {len(actual)} images to {output / 'store'}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", choices=DEVICES)
    parser.add_argument("output", type=Path, help="New output directory on Expand")
    parser.add_argument("--udid", help="Booted Apple simulator UDID")
    parser.add_argument("--packages", type=Path, help="Existing Swift package checkout cache")
    parser.add_argument("--xctestrun", type=Path, help="Reuse a compatible build-for-testing")
    parser.add_argument("--locale", action="append", choices=STORE_LOCALES, help="Capture a subset of locales")
    args = parser.parse_args()
    if args.device != "mac" and not args.udid:
        parser.error("--udid is required for simulator captures")
    samples = fixtures()
    capture(args, {locale: samples[locale] for locale in (args.locale or samples)})


if __name__ == "__main__":
    main()
