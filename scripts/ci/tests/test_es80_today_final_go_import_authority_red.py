#!/usr/bin/env python3
"""Expected-red proof that the historical Final GO import still carries authority."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

LEGACY_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"


def load_legacy():
    spec = importlib.util.spec_from_file_location("nembra_legacy_final_go_import_red", LEGACY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load legacy Final GO compatibility module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LegacyFinalGoImportAuthorityExpectedRedTests(unittest.TestCase):
    def test_default_imported_builder_fails_closed_before_foundation_authority(self):
        legacy = load_legacy()
        self.assertIs(
            legacy._trusted_xcode_subject,
            legacy._foundation._trusted_xcode_subject,
            "precondition: ordinary compatibility import still exposes the legacy trust subject",
        )

        delegated = False
        original = legacy._foundation.build_final_go_record

        def sentinel_builder(*args, **kwargs):
            nonlocal delegated
            delegated = True
            return {"decision": "GO", "unsafeSentinel": True}

        legacy._foundation.build_final_go_record = sentinel_builder
        try:
            with self.assertRaises(Exception):
                legacy.build_final_go_record()
        finally:
            legacy._foundation.build_final_go_record = original

        self.assertFalse(
            delegated,
            "a non-authorizing compatibility import must reject before delegating to the legacy authority foundation",
        )


if __name__ == "__main__":
    unittest.main()
