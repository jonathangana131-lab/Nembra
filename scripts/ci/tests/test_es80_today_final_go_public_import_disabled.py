#!/usr/bin/env python3
"""Prove the public Final-GO foundation import cannot construct an authority record."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest import mock

MODULE_DIR = Path(__file__).resolve().parents[1]
PUBLIC_PATH = MODULE_DIR / "es80_today_final_go_foundation.py"
HARDENED_PATH = MODULE_DIR / "es80_today_final_go_hardened.py"
PRIVATE_IMPL_NAME = "_es80_today_final_go_foundation_impl.py"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PublicFinalGoImportBoundaryTests(unittest.TestCase):
    def test_public_builder_fails_closed_before_private_validator(self) -> None:
        public = _load("nembra_public_final_go_import_probe", PUBLIC_PATH)
        private_calls: list[tuple[tuple[object, ...], dict[str, object]]] = []

        def forbidden_private_builder(*args, **kwargs):
            private_calls.append((args, kwargs))
            return {"decision": "GO"}

        with mock.patch.object(public._impl, "build_final_go_record", side_effect=forbidden_private_builder):
            with self.assertRaises(public.FinalGoError) as raised:
                public.build_final_go_record(candidate_root=Path("caller-controlled"))

        self.assertEqual(private_calls, [], "public compatibility builder reached private GO authority")
        self.assertIn("non-authorizing", str(raised.exception).lower())
        self.assertIn("es80_today_final_go_hardened.py", str(raised.exception))

    def test_hardened_composer_loads_private_validator_directly(self) -> None:
        hardened = _load("nembra_hardened_final_go_import_probe", HARDENED_PATH)
        self.assertEqual(Path(hardened.foundation.__file__).name, PRIVATE_IMPL_NAME)
        public = _load("nembra_public_final_go_comparison", PUBLIC_PATH)
        self.assertIsNot(hardened.foundation.build_final_go_record, public.build_final_go_record)


if __name__ == "__main__":
    unittest.main()
