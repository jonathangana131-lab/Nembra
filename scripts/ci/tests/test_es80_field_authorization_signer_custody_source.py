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

    def test_explicit_openssl_is_canonical_and_root_custodied(self):
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
        self.assertIn(
            'executable_stat.st_uid != 0',
            self.source,
            "The validated OpenSSL executable must be root-owned rather than replaceable by the signing user.",
        )
        self.assertIn(
            'directory_stat.st_uid != 0',
            self.source,
            "Every canonical OpenSSL custody directory must be root-owned so the signing user cannot swap the executable after validation.",
        )
        self.assertNotIn(
            'executable_stat.st_uid not in {0, signing_uid}',
            self.source,
            "Signing-user executable ownership reintroduces a validate-to-exec replacement race.",
        )

    def test_openssl_subprocess_does_not_inherit_signing_environment_or_stdin(self):
        self.assertIn(
            'env=controlled_openssl_environment()',
            self.source,
            "OpenSSL must run under a closed environment rather than inheriting provider/config/loader variables.",
        )
        self.assertIn(
            'stdin=subprocess.DEVNULL',
            self.source,
            "OpenSSL must not inherit an interactive stdin that can trigger passphrase prompts or hangs.",
        )
        self.assertIn(
            'stderr=subprocess.PIPE',
            self.source,
            "OpenSSL diagnostics must remain bounded inside the signer rather than leaking into the operator stream.",
        )
        self.assertIn(
            'timeout=OPENSSL_COMMAND_TIMEOUT_SECONDS',
            self.source,
            "Every OpenSSL subprocess must have one bounded execution deadline.",
        )
        self.assertNotIn(
            'stdout=subprocess.PIPE if capture_stdout else None',
            self.source,
            "Verification chatter must never contaminate the signer's JSON stdout.",
        )

    def test_openssl_subprocess_behaviorally_ignores_hostile_ambient_environment(self):
        namespace = runpy.run_path(str(SIGNER))
        run_openssl = namespace["run_openssl"]
        controlled_environment = namespace["controlled_openssl_environment"]()
        timeout_seconds = namespace["OPENSSL_COMMAND_TIMEOUT_SECONDS"]
        subprocess_module = namespace["subprocess"]
        captured = {}

        class Completed:
            returncode = 0
            stdout = b"fixture"
            stderr = b""

        def fake_run(*args, **kwargs):
            captured["args"] = args
            captured["kwargs"] = kwargs
            return Completed()

        hostile_environment = {
            "PATH": "/tmp/attacker-bin",
            "HOME": "/tmp/attacker-home",
            "OPENSSL_CONF": "/tmp/attacker-openssl.cnf",
            "OPENSSL_MODULES": "/tmp/attacker-modules",
            "OPENSSL_ENGINES": "/tmp/attacker-engines",
            "DYLD_INSERT_LIBRARIES": "/tmp/attacker.dylib",
            "LD_PRELOAD": "/tmp/attacker.so",
            "PYTHONPATH": "/tmp/attacker-python",
        }
        previous = {name: os.environ.get(name) for name in hostile_environment}
        os.environ.update(hostile_environment)
        try:
            with patch("subprocess.run", side_effect=fake_run):
                result = run_openssl(
                    "/usr/bin/openssl",
                    ["version"],
                    capture_stdout=True,
                )
        finally:
            for name, value in previous.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value

        self.assertEqual(result, b"fixture")
        self.assertEqual(captured["args"][0], ["/usr/bin/openssl", "version"])
        self.assertEqual(captured["kwargs"]["env"], controlled_environment)
        self.assertEqual(captured["kwargs"]["cwd"], "/")
        self.assertEqual(captured["kwargs"]["stdin"], subprocess_module.DEVNULL)
        self.assertEqual(captured["kwargs"]["stderr"], subprocess_module.PIPE)
        self.assertEqual(captured["kwargs"]["timeout"], timeout_seconds)
        self.assertEqual(controlled_environment["OPENSSL_CONF"], "/dev/null")
        self.assertEqual(controlled_environment["PATH"], "/usr/bin:/bin")
        for name in (
            "HOME",
            "OPENSSL_MODULES",
            "OPENSSL_ENGINES",
            "DYLD_INSERT_LIBRARIES",
            "LD_PRELOAD",
            "PYTHONPATH",
        ):
            self.assertNotIn(name, controlled_environment)

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
