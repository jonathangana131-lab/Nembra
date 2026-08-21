#!/usr/bin/env python3
from pathlib import Path
import unittest


CI_ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = CI_ROOT / "es80_run_materialized_field_authorization_signer.py"


class MaterializedSignerPostVerificationCustodySourceTests(unittest.TestCase):
    def test_verified_bytes_remain_the_only_execution_authority(self) -> None:
        source = RUNNER_PATH.read_text(encoding="utf-8")
        verify = source[
            source.index("def verify_materialized_bundle("):
            source.index("def parser()")
        ]
        main = source[source.index("def main("):]

        self.assertIn("verified_sources", verify)
        self.assertIn("return bundle, manifest, verified_sources", verify)
        self.assertIn("def _load_verified_module(", verify)
        self.assertIn("compile(source", verify)
        self.assertNotIn("spec_from_file_location", verify)

        self.assertIn("bundle, _, verified_sources = verify_materialized_bundle(", main)
        self.assertIn("verified_sources[os.fspath(WRAPPER_RELATIVE_PATH)]", main)
        self.assertIn("verified_sources[os.fspath(RENDEZVOUS_RELATIVE_PATH)]", main)
        self.assertIn("verified_sources[os.fspath(SIGNER_RELATIVE_PATH)]", main)
        self.assertIn("verified_sources[os.fspath(EVIDENCE_RELATIVE_PATH)]", main)
        self.assertIn("VERIFIED_SIGNER_BOOTSTRAP", main)
        self.assertIn("input=signer_input", main)

    def test_no_verified_source_path_is_reopened_after_bundle_verification(self) -> None:
        source = RUNNER_PATH.read_text(encoding="utf-8")
        main = source[source.index("def main("):]

        self.assertNotIn("_load_module(", main)
        self.assertNotIn("wrapper._load_rendezvous_helper(", main)
        self.assertNotIn("subprocess.run(\n            command,\n            cwd=bundle,\n            env=environment,\n            stdin=subprocess.DEVNULL", main)

        # The logical signer pathname may remain as __file__/argv provenance, but it must not be
        # the executable source supplied to Python after exact-byte verification.
        self.assertIn('"-c", VERIFIED_SIGNER_BOOTSTRAP', main)
        self.assertNotIn("str(signer),\n            cwd=bundle", main)


if __name__ == "__main__":
    unittest.main()
