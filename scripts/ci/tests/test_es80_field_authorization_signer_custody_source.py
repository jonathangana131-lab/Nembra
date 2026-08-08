#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

SIGNER = Path(__file__).resolve().parents[1] / "es80_field_authorization_envelope.py"


class OfflineFieldAuthorizationSignerCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = SIGNER.read_text()

    def test_signer_does_not_discover_openssl_from_ambient_path(self):
        self.assertNotIn(
            'shutil.which("openssl")',
            self.source,
            "The offline authority signer must not hand a private-key path to an ambient-PATH OpenSSL binary.",
        )
        self.assertNotRegex(
            self.source,
            re.compile(r"\bwhich\s*\(\s*['\"]openssl['\"]\s*\)"),
            "Any ambient PATH lookup for OpenSSL is a key-exfiltration surface.",
        )
        self.assertTrue(
            '--openssl' in self.source or 'NEMBRA_OPENSSL' in self.source,
            "The signer must select its OpenSSL executable through an explicit release-authority input.",
        )

    def test_explicit_openssl_is_canonical_and_not_repository_controlled(self):
        self.assertIn(
            '.resolve(',
            self.source,
            "The explicit OpenSSL path must be canonicalized before custody checks.",
        )
        self.assertTrue(
            'is_relative_to' in self.source
            or 'relative_to(' in self.source
            or 'repository' in self.source.lower(),
            "The signer must reject a repository-controlled OpenSSL executable.",
        )
        self.assertTrue(
            'stat.S_IMODE' in self.source or 'st_mode' in self.source,
            "The signer must inspect POSIX mode bits for the OpenSSL executable/custody path.",
        )
        self.assertTrue(
            '0o022' in self.source or '0o002' in self.source or 'world-writable' in self.source.lower(),
            "The signer must fail closed on writable executable/custody paths.",
        )

    def test_release_openssl_requires_root_owned_executable_subject(self):
        self.assertNotRegex(
            self.source,
            re.compile(r"executable_stat\.st_uid\s+not\s+in\s+\{\s*0\s*,\s*signing_uid\s*\}"),
            "A signing-user-owned OpenSSL remains replaceable by that same principal after path validation.",
        )
        self.assertRegex(
            self.source,
            re.compile(r"executable_stat\.st_uid\s*!=\s*0|executable_stat\.st_uid\s+not\s+in\s+\{\s*0\s*\}"),
            "Release OpenSSL must be rooted in a stronger custody principal than the signing user.",
        )

    def test_every_openssl_custody_directory_is_root_owned_and_not_group_world_writable(self):
        self.assertIn("directory_stat.st_uid", self.source)
        self.assertRegex(
            self.source,
            re.compile(r"directory_stat\.st_uid\s*!=\s*0|directory_stat\.st_uid\s+not\s+in\s+\{\s*0\s*\}"),
            "Mode-only parent checks still allow a directory owner to replace the executable path entry.",
        )
        self.assertIn("0o022", self.source)

    def test_private_key_requires_owner_only_posix_access(self):
        self.assertTrue(
            'stat.S_IMODE' in self.source or 'st_mode' in self.source,
            "The signer must inspect private-key POSIX mode bits.",
        )
        self.assertTrue(
            '0o077' in self.source or 'group/world' in self.source.lower(),
            "Group/world-readable private-key material must be rejected.",
        )
        self.assertTrue(
            'geteuid' in self.source or 'st_uid' in self.source,
            "Where POSIX ownership is available, the signing key must belong to the signing user.",
        )

    def test_no_private_key_or_secret_is_written_into_envelope_fields(self):
        lowered = self.source.lower()
        self.assertNotIn('"privatekey"', lowered)
        self.assertNotIn('"private_key"', lowered)
        self.assertNotIn('"privatekeypath"', lowered)
        self.assertNotIn('"private_key_path"', lowered)
        self.assertIn('signatureDERBase64', self.source)


if __name__ == "__main__":
    unittest.main()
