#!/usr/bin/env python3
"""Adversarial coverage for current-main and candidate worktree authority."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ISSUER_SPEC = importlib.util.spec_from_file_location("go", ROOT / "es80_authenticated_stationary_final_go.py")
if ISSUER_SPEC is None or ISSUER_SPEC.loader is None:
    raise RuntimeError("could not load Final-GO issuer")
go = importlib.util.module_from_spec(ISSUER_SPEC)
ISSUER_SPEC.loader.exec_module(go)

FIXTURE_SPEC = importlib.util.spec_from_file_location("go_fixture", Path(__file__).with_name("test_es80_authenticated_stationary_final_go.py"))
if FIXTURE_SPEC is None or FIXTURE_SPEC.loader is None:
    raise RuntimeError("could not load Final-GO fixture")
fixture = importlib.util.module_from_spec(FIXTURE_SPEC)
FIXTURE_SPEC.loader.exec_module(fixture)


class CurrentMainAndWorktreeCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nembra-final-go-current-main-")
        self.f = fixture.F(Path(self.temp.name))
        self.f.current_main = "0" * 40
        self.f.compare_status = "ahead"
        self.base_get = self.f.get

        def get(path: str):
            if path == "/branches/main":
                value = {"commit": {"sha": self.f.current_main}}
            elif path.startswith("/compare/"):
                base = path.split("/compare/", 1)[1].split("...", 1)[0]
                value = {"status": self.f.compare_status, "merge_base_commit": {"sha": base}}
            else:
                return self.base_get(path)
            return json.dumps(value).encode(), value

        self.f.get = get

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_current_main_must_be_exact_candidate_ancestor(self) -> None:
        record = self.f.build()
        self.assertEqual(record["acceptedPR"]["mainSHA"], self.f.current_main)
        self.f.compare_status = "diverged"
        with self.assertRaises(go.GoError):
            self.f.build()

    def test_main_movement_during_private_side_effect_forces_no_go(self) -> None:
        def move_main(repo, source, device):
            result = self.f.inst(repo, source, device)
            self.f.current_main = "1" * 40
            return result
        with self.assertRaises(go.GoError):
            self.f.build(run_installer=move_main)

    def test_hidden_index_flags_cannot_launder_candidate_authority_bytes(self) -> None:
        installer = self.f.repo / go.INSTALLER
        original = installer.read_text(encoding="utf-8")
        for flag, clear in (("--assume-unchanged", "--no-assume-unchanged"), ("--skip-worktree", "--no-skip-worktree")):
            subprocess.run(["/usr/bin/git", "-C", str(self.f.repo), "update-index", flag, go.INSTALLER], check=True)
            installer.write_text(original + "# hidden byte drift\n", encoding="utf-8")
            with self.assertRaises(go.GoError):
                go.candidate(self.f.repo, self.f.s)
            installer.write_text(original, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(self.f.repo), "update-index", clear, go.INSTALLER], check=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
