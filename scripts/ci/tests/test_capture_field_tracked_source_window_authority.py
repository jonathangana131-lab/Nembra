#!/usr/bin/env python3
"""Regression for exact tracked checkout custody across the field xcodebuild window."""
from __future__ import annotations

import importlib.util
import os
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

    def test_prearmed_untracked_build_visible_source_is_rejected(self) -> None:
        """A source inserted after the installer's raw audit must not survive guard admission."""
        guard = load_guard()

        class QuietBackend:
            def register(self, descriptor: int) -> None:
                del descriptor

            def events(self, timeout: float):
                del timeout
                return ()

            def close(self) -> None:
                pass

        class MinimalInputs:
            def __init__(self, root: Path, source_sha: str) -> None:
                self.accepted_source_root = root
                self.accepted_source_sha = source_sha

            def generation_snapshot(self):
                return ("stable-private-inputs",)

        with tempfile.TemporaryDirectory(prefix="nembra-tracked-window-prearmed-") as directory:
            root = Path(directory)
            repo = root / "repo"
            repo.mkdir()
            git(repo, "init", "-q")
            git(repo, "config", "user.name", "Nembra Test")
            git(repo, "config", "user.email", "nembra-test@example.invalid")
            sources = repo / "Sources"
            sources.mkdir()
            tracked = sources / "Capture.swift"
            tracked.write_text('let authority = "accepted"\n', encoding="utf-8")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "accepted")
            accepted_sha = git(repo, "rev-parse", "HEAD")

            # This models the real TOCTOU seam: the installer's earlier raw audit
            # has already passed, then an untracked Swift source becomes present
            # before the build guard enumerates the accepted Git tree and arms
            # vnode custody. Because the file is already present, no later vnode
            # event is required for the compiler to consume it.
            injected = sources / "Injected.swift"
            injected.write_text('let attacker = "compiled"\n', encoding="utf-8")
            consumed = root / "consumed.txt"

            original_watch_paths = guard._watch_paths
            guard._watch_paths = lambda _inputs: (repo,)
            try:
                with self.assertRaises(
                    guard.BuildGuardError,
                    msg="pre-armed untracked build-visible source escaped exact-source admission",
                ):
                    guard.run_guarded_build(
                        MinimalInputs(repo, accepted_sha),
                        ["/bin/sh", "-c", f'/bin/cat "{injected}" > "{consumed}"'],
                        backend_factory=QuietBackend,
                        poll_interval=0.001,
                        require_accepted_tracked_source=True,
                    )
            finally:
                guard._watch_paths = original_watch_paths

            self.assertFalse(
                consumed.exists(),
                "guard admitted a build command that consumed an unaccepted pre-armed source",
            )

    @unittest.skipUnless(sys.platform == "darwin", "requires real macOS kqueue vnode delivery")
    def test_real_macos_kqueue_reports_mutate_restore_before_compiler_can_be_accepted(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-tracked-window-kqueue-") as directory:
            root = Path(directory)
            source = root / "Capture.swift"
            accepted = 'let authority = "accepted"\n'
            source.write_text(accepted, encoding="utf-8")
            backend = guard.KqueueVnodeBackend()
            watched = ()
            try:
                watched = guard._open_watched_inputs((root, source), backend)
                self.assertFalse(backend.events(0), "unexpected vnode event before mutation")
                source.write_text('let authority = "attacker"\n', encoding="utf-8")
                source.write_text(accepted, encoding="utf-8")
                events = backend.events(1.0)
                self.assertTrue(events, "real macOS kqueue lost mutate-then-restore source evidence")
            finally:
                for descriptor, _ in watched:
                    try:
                        os.close(descriptor)
                    except OSError:
                        pass
                backend.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
