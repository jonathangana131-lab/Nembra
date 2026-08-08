#!/usr/bin/env python3
import os
from pathlib import Path
import re
import runpy
import unittest
from unittest.mock import patch

SIGNER = Path(__file__).resolve().parents[1] / "es80_field_authorization_envelope.py"


class OfflineFieldAuthorizationSignerCustodySourceTests(unittest.TestCase):
    def setUp(self):
        self.source = SIGNER.read_text()

    def test_signer_does_not_discover_or_override_openssl_from_ambient_environment(self):
        self.assertNotIn(
            'shutil.which("openssl")',
            self.source,
            "The offline authority signer must not hand a private-key descriptor to an ambient-PATH OpenSSL binary.",
        )
        self.assertNotRegex(
            self.source,
            re.compile(r"\bwhich\s*\(\s*['\"]openssl['\"]\s*\)"),
            "Any ambient PATH lookup for OpenSSL is a key-exfiltration surface.",
        )
        self.assertNotIn(
            "NEMBRA_OPENSSL",
            self.source,
            "Release signing must not let an inherited environment replace the reviewed system OpenSSL subject.",
        )
        self.assertIn(
            'DEFAULT_OPENSSL_PATH = "/usr/bin/openssl"',
            self.source,
            "The signer must select one fixed system OpenSSL subject.",
        )

    def test_system_openssl_and_every_custody_directory_are_root_owned(self):
        self.assertIn(
            "executable_stat.st_uid != 0",
            self.source,
            "The signer must reject a signing-user-owned OpenSSL executable that can be replaced at runtime.",
        )
        self.assertIn(
            "directory_stat.st_uid != 0",
            self.source,
            "Every parent directory in the canonical OpenSSL path must have root custody.",
        )
        self.assertIn(
            '.resolve(strict=True)',
            self.source,
            "The fixed OpenSSL path must be canonicalized before custody checks.",
        )
        self.assertTrue(
            'stat.S_IMODE' in self.source or 'st_mode' in self.source,
            "The signer must inspect POSIX mode bits for the OpenSSL executable/custody path.",
        )
        self.assertTrue(
            '0o022' in self.source or 'world-writable' in self.source.lower(),
            "The signer must fail closed on writable executable/custody paths.",
        )

    def test_openssl_subprocess_receives_only_the_fixed_minimal_environment(self):
        namespace = runpy.run_path(str(SIGNER))
        run_openssl = namespace["run_openssl"]
        expected_environment = namespace["OPENSSL_SUBPROCESS_ENVIRONMENT"]
        captured = {}

        class Completed:
            returncode = 0
            stdout = b"fixture"

        def fake_run(*args, **kwargs):
            captured.update(kwargs)
            return Completed()

        hostile_names = {
            "OPENSSL_CONF": "/tmp/attacker-openssl.cnf",
            "OPENSSL_MODULES": "/tmp/attacker-modules",
            "DYLD_INSERT_LIBRARIES": "/tmp/attacker.dylib",
            "LD_PRELOAD": "/tmp/attacker.so",
            "PYTHONPATH": "/tmp/attacker-python",
        }
        previous = {name: os.environ.get(name) for name in hostile_names}
        os.environ.update(hostile_names)
        try:
            with patch("subprocess.run", side_effect=fake_run):
                self.assertEqual(run_openssl("/usr/bin/openssl", ["version"], capture_stdout=True), b"fixture")
        finally:
            for name, value in previous.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value

        self.assertEqual(captured.get("env"), expected_environment)
        self.assertEqual(expected_environment.get("OPENSSL_CONF"), "/dev/null")
        for name in ("OPENSSL_MODULES", "DYLD_INSERT_LIBRARIES", "LD_PRELOAD", "PYTHONPATH"):
            self.assertNotIn(name, expected_environment)

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
