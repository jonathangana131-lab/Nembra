#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts" / "capture_tuya_private_input_provenance.py"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", HELPER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load provenance helper")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)

class TreeGenerationFenceTests(unittest.TestCase):
    def test_earlier_tree_child_mutate_restore_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            security = root / "security"
            identity = root / "identity"
            security.mkdir(); identity.mkdir()
            security_child = security / "blob.bin"
            security_child.write_bytes(b"AAAA")
            identity_child = identity / "identity.swift"
            identity_child.write_text("identity", encoding="utf-8")
            lockfile = root / "Podfile.lock"; lockfile.write_text("lock", encoding="utf-8")
            security_podspec = root / "security.podspec"; security_podspec.write_text("s", encoding="utf-8")
            identity_podspec = root / "identity.podspec"; identity_podspec.write_text("i", encoding="utf-8")
            original = provenance._tree_fingerprint
            mutated = False

            def wrapped(path: Path) -> str:
                nonlocal mutated
                result = original(path)
                if path == identity and not mutated:
                    security_child.write_bytes(b"BBBB")
                    security_child.write_bytes(b"AAAA")
                    mutated = True
                return result

            with mock.patch.object(provenance, "_tree_fingerprint", side_effect=wrapped):
                with self.assertRaises(provenance.ProvenanceError):
                    provenance.build_record(
                        lockfile=lockfile,
                        security_podspec=security_podspec,
                        security_build=security,
                        identity_podspec=identity_podspec,
                        identity_sources=identity,
                    )
            self.assertTrue(mutated)

if __name__ == "__main__":
    unittest.main()
