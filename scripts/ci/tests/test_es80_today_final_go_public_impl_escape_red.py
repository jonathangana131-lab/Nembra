#!/usr/bin/env python3
"""Expected-red guard: public Final GO facades must not expose authority-module objects."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import types
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_foundation.py"


def load_public_foundation():
    spec = importlib.util.spec_from_file_location("nembra_public_foundation_escape_red", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load public Final GO foundation")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PublicFoundationImplementationEscapeExpectedRedTests(unittest.TestCase):
    def test_public_globals_expose_no_authority_bearing_module_object(self) -> None:
        public = load_public_foundation()
        forbidden = []
        for name, value in vars(public).items():
            if not isinstance(value, types.ModuleType):
                continue
            if callable(getattr(value, "build_final_go_record", None)):
                forbidden.append((name, "build_final_go_record"))
            if callable(getattr(value, "publish_record_no_replace", None)):
                forbidden.append((name, "publish_record_no_replace"))
            if callable(getattr(value, "_trusted_xcode_subject", None)):
                forbidden.append((name, "_trusted_xcode_subject"))

        self.assertEqual(
            forbidden,
            [],
            f"public foundation leaked authority-bearing module globals: {forbidden!r}",
        )
        self.assertFalse(
            hasattr(public, "_impl"),
            "public foundation retained direct _impl escape to private Final GO authority",
        )


if __name__ == "__main__":
    unittest.main()
