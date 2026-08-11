#!/usr/bin/env python3
"""Regression for Final-GO control-module execution custody."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ISSUER = REPOSITORY / "scripts/ci/es80_authenticated_stationary_final_go.py"
SIGNED = REPOSITORY / "scripts/ci/es80_authenticated_stationary_signed_artifact.py"


def load_issuer():
    spec = importlib.util.spec_from_file_location("nembra_final_go_execution_custody", ISSUER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Final-GO issuer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FinalGoControlImportExecutionCustodyTests(unittest.TestCase):
    def test_unpinned_direct_signed_artifact_execution_fails_before_path_import(self) -> None:
        go = load_issuer()
        original = SIGNED.read_bytes()
        with tempfile.TemporaryDirectory(prefix="nembra-control-import-custody-") as temporary:
            marker = Path(temporary) / "mutable-path-executed"
            replacement = (
                "from pathlib import Path\n"
                f"Path({str(marker)!r}).write_text('executed', encoding='utf-8')\n"
                "def retain_and_reinspect(*args, **kwargs): return {'forged': True}\n"
                "def reinspect_retained(*args, **kwargs): return {'forged': True}\n"
            ).encode("utf-8")
            try:
                SIGNED.write_bytes(replacement)
                with self.assertRaises(go.GoError):
                    go.retained_signed_artifact(
                        REPOSITORY,
                        "0" * 40,
                        Path(temporary) / "device",
                        {},
                        Path(temporary) / "retained.ipa",
                    )
                self.assertFalse(marker.exists(), "mutable control-module pathname executed")
            finally:
                SIGNED.write_bytes(original)

    def test_pinned_source_executes_captured_bytes_not_mutable_path(self) -> None:
        go = load_issuer()
        original = SIGNED.read_bytes()
        with tempfile.TemporaryDirectory(prefix="nembra-control-import-custody-") as temporary:
            marker = Path(temporary) / "mutable-path-executed"
            replacement = (
                "from pathlib import Path\n"
                f"Path({str(marker)!r}).write_text('executed', encoding='utf-8')\n"
                "def retain_and_reinspect(*args, **kwargs): return {'forged': True}\n"
                "def reinspect_retained(*args, **kwargs): return {'forged': True}\n"
            ).encode("utf-8")
            pinned = (
                "def retain_and_reinspect(*args, **kwargs): return {'authority': 'accepted-pinned-source'}\n"
                "def reinspect_retained(*args, **kwargs): return {'authority': 'accepted-pinned-source'}\n"
            ).encode("utf-8")
            try:
                SIGNED.write_bytes(replacement)
                result = go.retained_signed_artifact(
                    REPOSITORY,
                    "0" * 40,
                    Path(temporary) / "device",
                    {},
                    Path(temporary) / "retained.ipa",
                    module_source=pinned,
                )
                self.assertEqual(result, {"authority": "accepted-pinned-source"})
                self.assertFalse(marker.exists(), "mutable control-module pathname executed")
            finally:
                SIGNED.write_bytes(original)

    def test_captured_control_source_must_match_accepted_git_blob_oid(self) -> None:
        go = load_issuer()
        with tempfile.TemporaryDirectory(prefix="nembra-control-source-capture-") as temporary:
            root = Path(temporary)
            relative = Path("scripts/ci/module.py")
            subject = root / relative
            subject.parent.mkdir(parents=True)
            accepted = b"VALUE = 'accepted'\n"
            subject.write_bytes(accepted)
            oid = go._git_blob_oid(accepted, "0" * 40)
            self.assertEqual(go._accepted_control_source(root, relative.as_posix(), oid), accepted)
            subject.write_bytes(b"VALUE = 'substituted'\n")
            with self.assertRaises(go.GoError):
                go._accepted_control_source(root, relative.as_posix(), oid)


if __name__ == "__main__":
    unittest.main(verbosity=2)
