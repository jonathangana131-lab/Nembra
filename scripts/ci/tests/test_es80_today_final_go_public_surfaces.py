#!/usr/bin/env python3
"""Permanent regressions for non-authorizing public Final GO Python surfaces."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

CI_DIR = Path(__file__).resolve().parents[1]


def load(filename: str, name: str):
    spec = importlib.util.spec_from_file_location(name, CI_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PublicFinalGoAuthoritySurfaceTests(unittest.TestCase):
    def test_historical_import_cannot_delegate_to_authority_builder(self):
        historical = load("es80_today_final_go_record.py", "nembra_public_final_go_record_test")
        self.assertFalse(hasattr(historical, "_trusted_xcode_subject"))
        with self.assertRaisesRegex(historical.FinalGoError, "non-authorizing"):
            historical.build_final_go_record()

    def test_public_foundation_import_cannot_delegate_to_authority_builder(self):
        foundation = load("es80_today_final_go_foundation.py", "nembra_public_final_go_foundation_test")
        self.assertFalse(hasattr(foundation, "_trusted_xcode_subject"))
        delegated = False

        def unsafe_builder(*args, **kwargs):
            nonlocal delegated
            delegated = True
            return {"decision": "GO"}

        with mock.patch.object(foundation._impl, "build_final_go_record", side_effect=unsafe_builder):
            with self.assertRaisesRegex(foundation.FinalGoError, "non-authorizing"):
                foundation.build_final_go_record()
        self.assertFalse(delegated)

    def test_public_foundation_main_and_publication_fail_before_authority(self):
        foundation = load("es80_today_final_go_foundation.py", "nembra_public_final_go_main_test")
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "FinalGO.json"
            with mock.patch.object(foundation._impl, "build_final_go_record") as builder, mock.patch.object(
                foundation._impl, "publish_record_no_replace"
            ) as publisher:
                status = foundation.main(["--output", str(output)])
                with self.assertRaisesRegex(foundation.FinalGoError, "non-authorizing"):
                    foundation.publish_record_no_replace(output, b'{"decision":"GO"}\n')
            self.assertEqual(status, 2)
            builder.assert_not_called()
            publisher.assert_not_called()
            self.assertFalse(output.exists())

    def test_hardened_entrypoint_uses_private_implementation_not_public_facades(self):
        hardened = load("es80_today_final_go_hardened.py", "nembra_hardened_final_go_surface_test")
        self.assertEqual(
            Path(hardened.foundation.__file__).name,
            "_es80_today_final_go_foundation_impl.py",
        )
        self.assertTrue(callable(hardened.foundation.build_final_go_record))


if __name__ == "__main__":
    unittest.main()
