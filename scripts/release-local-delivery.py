#!/usr/bin/env python3
"""Deliver locally built Jotley releases using Bitwarden Secrets Manager."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import time
from contextlib import contextmanager
from email.utils import formatdate
from typing import Any, Iterator
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
from zipfile import ZipFile


class Secrets:
    def __init__(self) -> None:
        self.environment = os.environ.copy()
        if not self.environment.get("BWS_ACCESS_TOKEN"):
            self.environment["BWS_ACCESS_TOKEN"] = subprocess.check_output(
                ["launchctl", "getenv", "BWS_ACCESS_TOKEN"], text=True
            ).strip()
        self.ids = {}
        for item in self.read("secret", "list"):
            self.ids.setdefault(item["key"], []).append(item["id"])

    def read(self, *args: str) -> Any:
        result = subprocess.run(["bws", *args, "-o", "json"], env=self.environment, capture_output=True)
        if result.returncode:
            raise SystemExit("Bitwarden Secrets Manager access failed. Check bws and the machine account.")
        return json.loads(result.stdout)

    def get(self, name: str) -> str:
        ids = self.ids.get(name, [])
        if len(ids) != 1:
            raise SystemExit(f"Expected one accessible Bitwarden Secrets Manager entry named {name}.")
        return self.read("secret", "get", ids[0])["value"].strip()


@contextmanager
def apple_credentials(store: Secrets) -> Iterator[tuple[str, str, Path]]:
    prefix = os.environ.get("JOTLEY_ASC_SECRET_PREFIX", "INKSPRING_ASC_UPLOAD")
    key_id = store.get(prefix + "_KEY_ID")
    issuer = store.get(prefix + "_ISSUER_ID")
    with tempfile.TemporaryDirectory() as temporary:
        key = Path(temporary) / f"AuthKey_{key_id}.p8"
        key.touch(mode=0o600)
        key.write_text(store.get(prefix + "_PRIVATE_KEY").replace("\\n", "\n") + "\n")
        yield key_id, issuer, key


def notarize(archive: Path, receipt: Path, store: Secrets) -> None:
    with apple_credentials(store) as (key_id, issuer, key), receipt.open("w") as output:
        subprocess.run(["xcrun", "notarytool", "submit", str(archive), "--key", str(key),
                        "--key-id", key_id, "--issuer", issuer, "--wait", "--timeout", "12m",
                        "--output-format", "json"], stdout=output, check=True)
    result = json.loads(receipt.read_text())
    if result["status"] != "Accepted":
        raise SystemExit(f"Notarization {result['status']}. See {receipt}.")
    print(f"Notarization accepted for {archive.name}.")


def apple_api(endpoint: str, key_id: str, issuer: str, key: Path,
              token_cache: dict[str, Any], data: Any = None) -> Any:
    now = int(time.time())
    if now >= token_cache.get("refresh_at", 0):
        signer = """
const { sign } = require('node:crypto');
const { readFileSync } = require('node:fs');
const [file, kid, iss, iat] = process.argv.slice(1);
const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const body = encode({ alg: 'ES256', kid, typ: 'JWT' }) + '.' +
  encode({ iss, iat: Number(iat), exp: Number(iat) + 900, aud: 'appstoreconnect-v1' });
const sig = sign('sha256', Buffer.from(body), { key: readFileSync(file), dsaEncoding: 'ieee-p1363' });
process.stdout.write(body + '.' + sig.toString('base64url'));
"""
        token_cache.update(token=subprocess.check_output(
            ["node", "-e", signer, str(key), key_id, issuer, str(now)], text=True
        ), refresh_at=now + 840)
    body = json.dumps({"data": data}).encode() if data is not None else None
    request = Request("https://api.appstoreconnect.apple.com/v1/" + endpoint, data=body, headers={
        "Authorization": "Bearer " + token_cache["token"], "Content-Type": "application/json"
    })
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)["data"] if response.status != 204 else None
    except HTTPError as error:
        raise SystemExit(f"App Store Connect returned HTTP {error.code} for {endpoint}.") from None


def testflight(archive: Path, app: str, group_name: str, resume: bool, store: Secrets) -> None:
    with ZipFile(archive) as package:
        (plist,) = [name for name in package.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        info = plistlib.loads(package.read(plist))
    number, version = info["CFBundleVersion"], info["CFBundleShortVersionString"]
    query = urlencode({"filter[app]": app, "filter[version]": number, "limit": 20})
    with apple_credentials(store) as (key_id, issuer, key):
        token_cache: dict[str, Any] = {}

        def api(endpoint: str, data: Any = None) -> Any:
            return apple_api(endpoint, key_id, issuer, key, token_cache, data)

        def matching_build() -> Any:
            for row in api("builds?" + query):
                attributes = api(f"builds/{row['id']}/preReleaseVersion")["attributes"]
                if attributes["platform"] == "IOS" and attributes["version"] == version:
                    return row
            return None

        listing = api("apps/" + app)["attributes"]
        if listing["bundleId"] != info["CFBundleIdentifier"]:
            raise SystemExit("The archive does not match the requested App Store listing.")
        (group,) = [item for item in api(f"apps/{app}/betaGroups?limit=200")
                    if item["attributes"]["name"] == group_name and item["attributes"]["isInternalGroup"]]
        if not matching_build() and not resume:
            subprocess.run(["xcrun", "altool", "--upload-app", "-f", str(archive), "-t", "ios",
                            "--apiKey", key_id, "--apiIssuer", issuer],
                           env={**os.environ, "API_PRIVATE_KEYS_DIR": str(key.parent)}, check=True)
        for _ in range(90):
            row = matching_build()
            if row and row["attributes"]["processingState"] == "VALID":
                break
            if row and row["attributes"]["processingState"] in {"INVALID", "FAILED"}:
                raise SystemExit(f"Apple could not process build {number}.")
            time.sleep(10)
        else:
            raise SystemExit("Apple is still processing. Re-run with --resume to check it without uploading again.")
        build_id = row["id"]
        memberships = f"betaGroups/{group['id']}/relationships/builds"
        def in_group() -> bool:
            return group["attributes"]["hasAccessToAllBuilds"] or any(
                item["id"] == build_id for item in api(memberships + "?limit=200")
            )

        if not in_group():
            api(memberships, [{"type": "builds", "id": build_id}])
        for _ in range(40):
            beta = api(f"builds/{build_id}/buildBetaDetail")["attributes"]
            if beta["internalBuildState"] == "IN_BETA_TESTING" and in_group():
                print(f"{version} ({number}) verified in TestFlight for {group_name}.")
                return
            time.sleep(5)
        raise SystemExit("Apple has yet to confirm internal testing. Check build status before retrying.")


def mac_stage(args: argparse.Namespace, store: Secrets) -> None:
    archive = args.archive.resolve()
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if archive.name != f"Jotley-{version}-{build}.dmg" or info.get("SUFeedURL") != "https://jotley.ai/appcast.xml":
        raise SystemExit("The installer filename, Mac app version, and production Sparkle feed must match.")
    subprocess.run(["xcrun", "stapler", "validate", str(archive)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
    if args.signature:
        signature = args.signature.read_text().strip()
    else:
        if not args.sign_tool:
            raise SystemExit("Supply --sign-tool for a local signature or --signature for a verified Actions artifact.")
        signed = subprocess.run([str(args.sign_tool.resolve()), "--ed-key-file", "-", str(archive)], text=True,
                                input=store.get(args.sparkle_secret) + "\n", capture_output=True, check=True)
        match = re.search(r'sparkle:edSignature="([^"]+)"', signed.stdout)
        if not match:
            raise SystemExit("Sparkle signing did not return a signature.")
        signature = match.group(1)
    verify = """
const { createPublicKey, verify } = require('node:crypto');
const { readFileSync } = require('node:fs');
const [file, publicKey, signature] = process.argv.slice(1);
const key = createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'),
  Buffer.from(publicKey, 'base64')]), type: 'spki', format: 'der' });
if (!verify(null, readFileSync(file), key, Buffer.from(signature, 'base64'))) process.exit(1);
"""
    subprocess.run(["node", "-e", verify, str(archive), info["SUPublicEDKey"], signature], check=True)
    endpoint = args.r2_endpoint.rstrip("/")
    if not re.fullmatch(r"https://[a-f0-9]{32}\.r2\.cloudflarestorage\.com", endpoint):
        raise SystemExit("Use the configured HTTPS Cloudflare R2 S3 endpoint.")
    with archive.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    config = "user = " + json.dumps(store.get("CLOUDFLARE_R2_ACCESS_KEY_ID") + ":" +
                                    store.get("CLOUDFLARE_R2_SECRET_ACCESS_KEY")) + "\n"
    result = subprocess.run(["/usr/bin/curl", "-sS", "-K", "-", "--aws-sigv4", "aws:amz:auto:s3",
                             "--upload-file", str(archive), "--max-time", "180",
                             "--header", "If-None-Match: *", "--header", f"x-amz-content-sha256: {digest}",
                             "--header", "Content-Type: application/x-apple-diskimage",
                             "--header", f'Content-Disposition: attachment; filename="{archive.name}"',
                             "--output", os.devnull, "--write-out", "%{http_code}",
                             endpoint + "/jotley-media/downloads/" + archive.name],
                            input=config, capture_output=True, text=True, check=True)
    if result.stdout not in {"200", "201", "412"}:
        raise SystemExit(f"R2 upload returned HTTP {result.stdout}.")
    url = "https://jotley.ai/" + archive.name
    # The media host's bot filter rejects Python's default user agent.
    check = Request(url + "?" + urlencode({"verify": digest[:16]}), headers={"User-Agent": "JotleyRelease/1.0"})
    with urlopen(check, timeout=90) as response:
        if hashlib.file_digest(response, "sha256").hexdigest() != digest:
            raise SystemExit("The public download does not match the notarized installer.")
    stage_website(args.output, archive, info, signature, digest, url, args.description)


def stage_website(output: Path, archive: Path, info: dict[str, Any], signature: str,
                  digest: str, url: str, description: str) -> None:
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    size = archive.stat().st_size
    output.mkdir(parents=True, exist_ok=False)
    manifest = {"version": version, "build": int(build), "file": archive.name, "bytes": size, "sha256": digest}
    (output / "mac-release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", sparkle)
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Jotley"
    item = ET.SubElement(channel, "item")
    for key, value in {
        "title": version, "pubDate": formatdate(usegmt=True), "description": description,
        f"{{{sparkle}}}version": build, f"{{{sparkle}}}shortVersionString": version,
        f"{{{sparkle}}}minimumSystemVersion": info["LSMinimumSystemVersion"]
    }.items():
        ET.SubElement(item, key).text = value
    ET.SubElement(item, "enclosure", {"url": url, "length": str(size), "type": "application/octet-stream",
                                      f"{{{sparkle}}}edSignature": signature})
    ET.indent(root)
    ET.ElementTree(root).write(output / "appcast.xml", encoding="utf-8", xml_declaration=True)
    print(f"Verified {url}. Review the two website files in {output}.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    notary = commands.add_parser("notarize")
    notary.add_argument("archive", type=Path)
    notary.add_argument("receipt", type=Path)
    mobile = commands.add_parser("testflight")
    mobile.add_argument("archive", type=Path)
    mobile.add_argument("--app", default="6746770199")
    mobile.add_argument("--group", default="Jotley Home")
    mobile.add_argument("--resume", action="store_true")
    mac = commands.add_parser("mac-stage")
    mac.add_argument("archive", type=Path)
    mac.add_argument("--app", type=Path, required=True)
    mac.add_argument("--r2-endpoint", required=True)
    mac.add_argument("--output", type=Path, required=True)
    mac.add_argument("--description", required=True)
    signature = mac.add_mutually_exclusive_group(required=True)
    signature.add_argument("--sign-tool", type=Path)
    signature.add_argument("--signature", type=Path)
    mac.add_argument("--sparkle-secret", default="JOTLEY_SPARKLE_EDDSA_PRIVATE_KEY")
    args = parser.parse_args()
    store = Secrets()
    if args.command == "notarize":
        notarize(args.archive, args.receipt, store)
    elif args.command == "testflight":
        testflight(args.archive.resolve(), args.app, args.group, args.resume, store)
    else:
        mac_stage(args, store)


if __name__ == "__main__":
    main()
