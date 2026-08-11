#!/usr/bin/env python3
"""Regression for exact tracked checkout custody across the field xcodebuild window."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
GUARD_PATH = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


def load_guard():
    spec = importlib.util.spec_from_file_location("nembra_tracked_source_window_guard", GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("build guard import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def git(cwd: Path, *args: str) -> str:
    return subprocess.check_output(["/usr/bin/git", *args], cwd=cwd, text=True).strip()


class CaptureFieldTrackedSourceWindowAuthorityTests(unittest.TestCase):
    def test_manifest_binds_exact_git_bytes_and_detects_restore_sensitive_mutation(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-tracked-window-") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            git(repo, "init", "-q")
            git(repo, "config", "user.name", "Nembra Test")
            git(repo, "config", "user.email", "nembra-test@example.invalid")
            source = repo / "Capture.swift"
            nested = repo / "NembraCapture.xcodeproj" / "project.pbxproj"
            nested.parent.mkdir()
            source.write_text('let authority = "accepted"\n', encoding="utf-8")
            nested.write_text("// accepted project graph\n", encoding="utf-8")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "accepted")
            accepted_sha = git(repo, "rev-parse", "HEAD")

            manifest = guard._accepted_tracked_source_manifest(repo, accepted_sha)
            relative = {item.path.relative_to(repo).as_posix() for item in manifest}
            self.assertEqual(relative, {"Capture.swift", "NembraCapture.xcodeproj/project.pbxproj"})
            guard._verify_tracked_source_manifest(manifest)

            watch_paths = set(guard._tracked_source_watch_paths(manifest, repo))
            self.assertIn(repo, watch_paths)
            self.assertIn(source, watch_paths)
            self.assertIn(nested.parent, watch_paths)
            self.assertIn(nested, watch_paths)

            source.write_text('let authority = "attacker"\n', encoding="utf-8")
            with self.assertRaises(guard.BuildGuardError):
                guard._verify_tracked_source_manifest(manifest)

    def test_field_cli_requires_exact_source_tree_through_guarded_build(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        guard = GUARD_PATH.read_text(encoding="utf-8")
        start = installer.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')
        end = installer.index('verify_private_tuya_inputs\nverify_accepted_checkout_source', start)
        build_window = installer[start:end]

        self.assertIn('--accepted-source-root "$ROOT"', build_window)
        self.assertIn('--accepted-source-sha "$SOURCE_SHA"', build_window)
        self.assertIn('-workspace NembraCapture.xcworkspace', build_window)
        self.assertIn("def _accepted_tracked_source_manifest", guard)
        self.assertIn("def _verify_tracked_source_manifest", guard)
        self.assertIn("def _tracked_source_watch_paths", guard)
        self.assertIn("require_accepted_tracked_source=True", guard)
        self.assertIn("KQ_NOTE_ATTRIB", guard)

    def test_symlink_or_nonblob_tracked_subject_fails_closed(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-tracked-window-symlink-") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            git(repo, "init", "-q")
            git(repo, "config", "user.name", "Nembra Test")
            git(repo, "config", "user.email", "nembra-test@example.invalid")
            target = repo / "real.swift"
            target.write_text("let accepted = true\n", encoding="utf-8")
            (repo / "linked.swift").symlink_to("real.swift")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "symlink")
            accepted_sha = git(repo, "rev-parse", "HEAD")

            with self.assertRaises(guard.BuildGuardError):
                guard._accepted_tracked_source_manifest(repo, accepted_sha)


if __name__ == "__main__":
    unittest.main(verbosity=2)
