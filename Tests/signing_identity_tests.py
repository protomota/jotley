"""Signing selection tests; no private-key use or keychain mutation."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("signing_identity", Path(__file__).resolve().parents[1] / "scripts/signing_identity.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningIdentityTests(unittest.TestCase):
    def test_exact_identity_and_fingerprint(self) -> None:
        listing = ' 1) ' + 'A' * 40 + ' "Developer ID Application: Example (TEAM)"\n'
        self.assertEqual(signing.resolve_identity(listing, 'a' * 40, 'developer-id'), 'A' * 40)
        self.assertEqual(signing.resolve_identity(listing, 'Developer ID Application: Example (TEAM)'), 'A' * 40)

    def test_absent_and_revoked_do_not_fall_back(self) -> None:
        for listing in ['', ' 1) ' + 'A' * 40 + ' "Developer ID Application: Example (TEAM)" (CSSMERR_TP_CERT_REVOKED)']:
            with self.assertRaisesRegex(ValueError, 'System keychain fallback is disabled'):
                signing.resolve_identity(listing, 'Developer ID Application')

    def test_distribution_classes_are_not_interchangeable(self) -> None:
        listing = ' 1) ' + 'B' * 40 + ' "Apple Distribution: Example (TEAM)"'
        self.assertEqual(signing.resolve_identity(listing, 'Apple Distribution', 'app-store'), 'B' * 40)
        with self.assertRaisesRegex(ValueError, 'requires a Developer ID Application'):
            signing.resolve_identity(listing, 'B' * 40, 'developer-id')

    def test_ambiguous_generic_name_requires_exact_choice(self) -> None:
        listing = '\n'.join(' 1) ' + char * 40 + f' "Apple Development: Example {char}"' for char in ['A', 'B'])
        with self.assertRaisesRegex(ValueError, 'More than one'):
            signing.resolve_identity(listing, 'Apple Development')

    def test_preflight_queries_only_login_and_never_signs(self) -> None:
        listing = ' 1) ' + 'A' * 40 + ' "Developer ID Application: Example (TEAM)"'
        with patch.object(signing.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=listing)) as run:
            self.assertEqual(signing.local_signing_identity('Developer ID Application'), 'A' * 40)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0], ['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning', str(Path.home() / 'Library/Keychains/login.keychain-db')])


if __name__ == '__main__':
    unittest.main()
