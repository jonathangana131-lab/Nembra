#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

SIGNER = Path(__file__).resolve().parents[1] / "es80_field_authorization_envelope.py"


class OfflineOpenSSLRootCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = SIGNER.read_text(encoding="utf-8")

    def test_release_openssl_must_not_trust_signing_user_owned_binary(self):
        self.assertNotRegex(
            self.source,
            re.compile(r"st_uid\s+not\s+in\s+\{\s*0\s*,\s*signing_uid\s*\}"),
            "A signing-user-owned OpenSSL can be replaced by that same authority user after path validation; release OpenSSL must be rooted in a stronger custody principal.",
        )
        self.assertRegex(
            self.source,
            re.compile(r"executable_stat\.st_uid\s*!=\s*0|executable_stat\.st_uid\s+not\s+in\s+\{\s*0\s*\}"),
            "The OpenSSL executable itself must be root-owned before private-key access is delegated to it.",
        )

    def test_every_openssl_custody_directory_must_be_root_owned(self):
        self.assertIn("directory_stat.st_uid", self.source)
        self.assertRegex(
            self.source,
            re.compile(r"directory_stat\.st_uid\s*!=\s*0|directory_stat\.st_uid\s+not\s+in\s+\{\s*0\s*\}"),
            "Mode-only parent-directory checks are insufficient: an unrelated/user owner of a 0755 directory can replace path entries.",
        )
        self.assertIn("0o022", self.source)

    def test_custom_openssl_remains_allowed_only_under_root_custody(self):
        # NEMBRA_OPENSSL may select an alternate reviewed binary, but selection is not authority.
        # The executable and every canonical ancestor still need the same root-owned custody rule.
        self.assertIn("NEMBRA_OPENSSL", self.source)
        self.assertIn("resolve(strict=True)", self.source)
        self.assertIn("path_is_within(resolved, REPOSITORY_ROOT)", self.source)


if __name__ == "__main__":
    unittest.main()
