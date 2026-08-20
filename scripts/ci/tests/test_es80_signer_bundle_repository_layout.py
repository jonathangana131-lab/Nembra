#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import stat
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_sign_field_authorization_from_rendezvous.py"
SPEC = importlib.util.spec_from_file_location("sign_from_rendezvous_bundle_layout", SCRIPT)
assert SPEC and SPEC.loader
wrapper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wrapper)


class SignerBundleRepositoryLayoutTests(unittest.TestCase):
    def test_frozen_sources_preserve_repository_relative_layout(self) -> None:
        with wrapper.accepted_execution_bundle() as bundle:
            bundle = bundle.resolve()
            for relative in wrapper.EXECUTION_SOURCES:
                source = bundle / relative
                with self.subTest(relative=relative):
                    self.assertTrue(source.is_file())
                    self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o400)
                    self.assertFalse(
                        (bundle / Path(relative).name).exists(),
                        "accepted source must not be flattened into the bundle root",
                    )

            self.assertEqual(stat.S_IMODE((bundle / "scripts").stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((bundle / "scripts/ci").stat().st_mode), 0o700)
            self.assertEqual((bundle / "scripts").stat().st_uid, os.geteuid())
            self.assertEqual((bundle / "scripts/ci").stat().st_uid, os.geteuid())

    def test_frozen_signer_keeps_its_repository_root_at_bundle_root(self) -> None:
        with wrapper.accepted_execution_bundle() as bundle:
            bundle = bundle.resolve()
            signer = (bundle / wrapper.SIGNER_RELATIVE_PATH).resolve()
            rendezvous = (bundle / wrapper.RENDEZVOUS_RELATIVE_PATH).resolve()

            self.assertEqual(signer.parents[2], bundle)
            self.assertEqual(rendezvous.parents[2], bundle)
            self.assertEqual(signer.parent, rendezvous.parent)
            self.assertTrue((signer.parent / "es80_signed_field_artifact_evidence.py").is_file())

    def test_frozen_relative_paths_keep_basename_compatibility_aliases(self) -> None:
        self.assertEqual(wrapper.SIGNER_BASENAME, wrapper.SIGNER_RELATIVE_PATH.name)
        self.assertEqual(wrapper.RENDEZVOUS_BASENAME, wrapper.RENDEZVOUS_RELATIVE_PATH.name)

    def test_wrapper_no_longer_uses_basename_flattening(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("root / Path(relative).name", source)
        self.assertIn("destination = _prepare_bundle_parent(root, relative_path)", source)
        self.assertIn("bundle / SIGNER_RELATIVE_PATH", source)
        self.assertIn("bundle / RENDEZVOUS_RELATIVE_PATH", source)


if __name__ == "__main__":
    unittest.main()
