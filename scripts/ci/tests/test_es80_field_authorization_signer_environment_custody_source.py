#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

SIGNER = Path(__file__).resolve().parents[1] / "es80_field_authorization_envelope.py"


class OfflineFieldAuthorizationSignerEnvironmentCustodySourceTests(unittest.TestCase):
    """Pin ambient-process environment as part of OpenSSL executable custody.

    The signer intentionally passes the private-key descriptor to the selected OpenSSL process.
    Pinning only the executable pathname is therefore insufficient if that process can still load
    attacker-selected configuration, provider/engine modules, or dynamic-loader libraries from
    inherited environment variables before it consumes the key descriptor.
    """

    def setUp(self):
        self.source = SIGNER.read_text()
        match = re.search(
            r"def run_openssl\([\s\S]*?\n\ndef ",
            self.source,
        )
        self.assertIsNotNone(match, "Could not isolate run_openssl source")
        self.run_openssl_source = match.group(0)

    def test_openssl_subprocess_receives_an_explicit_environment(self):
        self.assertRegex(
            self.run_openssl_source,
            re.compile(r"subprocess\.run\([\s\S]*?\benv\s*=", re.MULTILINE),
            "The trusted OpenSSL executable must not inherit the signing shell environment implicitly.",
        )

    def test_environment_contract_addresses_code_loading_inputs(self):
        # Accept either a strict allowlist or an explicit deny/scrub implementation, but make the
        # dangerous families visible in the production contract so future refactors cannot quietly
        # restore ambient code-loading authority.
        required_markers = (
            "LD_PRELOAD",
            "LD_LIBRARY_PATH",
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "OPENSSL_CONF",
            "OPENSSL_MODULES",
            "OPENSSL_ENGINES",
        )
        missing = [marker for marker in required_markers if marker not in self.source]
        self.assertEqual(
            missing,
            [],
            "Signer does not explicitly neutralize ambient OpenSSL/dynamic-loader code-loading inputs: "
            + ", ".join(missing),
        )

    def test_private_key_fd_is_not_given_to_an_ambient_environment_process(self):
        self.assertIn(
            "pass_fds=(descriptor,)",
            self.source,
            "This diagnostic assumes the current signer deliberately inherits the exact key descriptor.",
        )
        self.assertNotRegex(
            self.run_openssl_source,
            re.compile(r"env\s*=\s*os\.environ\s*(?:,|\))"),
            "Passing os.environ unchanged does not close ambient executable/module custody.",
        )


if __name__ == "__main__":
    unittest.main()
