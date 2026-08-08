#!/usr/bin/env python3
from pathlib import Path
import unittest

SIGNER = Path(__file__).resolve().parents[1] / "es80_field_authorization_envelope.py"


class OfflineSignerSubprocessEnvironmentSourceTests(unittest.TestCase):
    def setUp(self):
        self.source = SIGNER.read_text(encoding="utf-8")

    def test_openssl_subprocess_does_not_inherit_ambient_environment(self):
        start = self.source.index("def run_openssl(")
        end = self.source.index("\ndef snapshot_private_key(", start)
        function = self.source[start:end]

        self.assertIn("subprocess.run(", function)
        self.assertIn(
            "env=",
            function,
            "The trusted OpenSSL pathname is insufficient if the subprocess still inherits attacker-controlled loader/OpenSSL configuration variables.",
        )

    def test_signer_explicitly_accounts_for_loader_and_openssl_configuration_inputs(self):
        source_upper = self.source.upper()
        for marker in (
            "OPENSSL_CONF",
            "OPENSSL_MODULES",
            "OPENSSL_ENGINES",
            "DYLD_",
            "LD_",
        ):
            self.assertIn(
                marker,
                source_upper,
                f"Signer custody must explicitly sanitize or reject ambient {marker} influence before invoking OpenSSL.",
            )


if __name__ == "__main__":
    unittest.main()
