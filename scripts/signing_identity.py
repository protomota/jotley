"""Read-only, login-keychain-only preflight for local Mac signing."""
import argparse
from pathlib import Path
import re
import subprocess


KINDS = {"development": "Apple Development", "developer-id": "Developer ID Application", "app-store": "Apple Distribution"}


def resolve_identity(listing: str, requested: str, kind: str | None = None) -> str:
    matches = []
    for line in listing.splitlines():
        # Invalid/revoked identities have an error suffix; never select them.
        match = re.fullmatch(r'\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"]+)"\s*', line)
        if not match:
            continue
        fingerprint, name = match.groups()
        if requested.casefold() == fingerprint.casefold() or requested == name or requested in KINDS.values() and name.startswith(requested + ":"):
            matches.append((fingerprint, name))
    if not matches:
        raise ValueError("Required signing identity is missing or invalid in ~/Library/Keychains/login.keychain-db. Import the existing identity into login and verify its authorization before signing. System keychain fallback is disabled.")
    if len(matches) != 1:
        raise ValueError("More than one matching identity is in login. Set the exact certificate name or SHA-1 fingerprint.")
    fingerprint, name = matches[0]
    if not any(name.startswith(prefix + ":") for prefix in KINDS.values()):
        raise ValueError("Select an Apple Development, Developer ID Application or Apple Distribution identity for the app.")
    if kind and not name.startswith(KINDS[kind] + ":"):
        raise ValueError(f"This build requires a {KINDS[kind]} identity, not {name.split(':')[0]}.")
    return fingerprint.upper()


def local_signing_identity(requested: str, kind: str | None = None) -> str:
    keychain = Path.home() / "Library/Keychains/login.keychain-db"
    result = subprocess.run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning", str(keychain)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError("Could not inspect the login keychain. Unlock it using macOS, then retry; no System keychain fallback is allowed.")
    return resolve_identity(result.stdout, requested, kind)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("identity")
    parser.add_argument("--kind", choices=KINDS)
    args = parser.parse_args()
    try:
        print(local_signing_identity(args.identity, args.kind))
    except ValueError as error:
        parser.exit(1, f"Signing preflight: {error}\n")


if __name__ == "__main__":
    main()
