#!/usr/bin/env python3
"""Expected-red regression for untracked build-visible source injection before vnode arming."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
GUARD_PATH = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"


def load_guard():
    spec = importlib.util.spec_from_file_location("nembra_untracked_prearm_guard", GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("build guard import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def git(cwd: Path, *args: str) -> str:
    return subprocess.check_output(["/usr/bin/git", *args], cwd=cwd, text=True).strip()


class QuietBackend:
    """Models a vnode backend armed only after the injected directory entry already exists."""

    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        del timeout
        return ()

    def close(self) -> None:
        pass


class ImmediateProcess:
    def __init__(self, consumed: list[str], repo: Path) -> None:
        consumed.extend(
            sorted(path.relative_to(repo).as_posix() for path in repo.rglob("*.swift"))
        )
        self.returncode = 0

    def poll(self):
        return 0

    def terminate(self) -> None:
        self.returncode = -15

    def wait(self, timeout=None):
        del timeout
        return self.returncode

    def kill(self) -> None:
        self.returncode = -9


class StableInputs:
    def __init__(self, root: Path, source_sha: str) -> None:
        self.accepted_source_root = root
        self.accepted_source_sha = source_sha

    def generation_snapshot(self):
        return ("stable-private-and-generated-inputs",)


class CaptureFieldUntrackedPrearmInjectionRedTeamTests(unittest.TestCase):
    def test_untracked_source_inserted_between_endpoint_audit_and_vnode_arming_is_rejected(self) -> None:
        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-untracked-prearm-") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            git(repo, "init", "-q")
            git(repo, "config", "user.name", "Nembra Test")
            git(repo, "config", "user.email", "nembra-test@example.invalid")

            app_sources = repo / "NembraApp" / "App"
            app_sources.mkdir(parents=True)
            tracked = app_sources / "Tracked.swift"
            tracked.write_text('let authority = "accepted"\n', encoding="utf-8")
            project = repo / "NembraCapture.xcodeproj" / "project.pbxproj"
            project.parent.mkdir()
            project.write_text("// accepted project graph\n", encoding="utf-8")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "accepted")
            accepted_sha = git(repo, "rev-parse", "HEAD")
            self.assertEqual(git(repo, "status", "--porcelain=v1", "--untracked-files=all"), "")

            injected = app_sources / "Injected.swift"
            consumed: list[str] = []
            original_watch_paths = guard._watch_paths
            original_open_watched_inputs = guard._open_watched_inputs

            # The production installer performs a raw accepted-checkout audit before
            # it enters run_guarded_build(). This wrapper models a same-UID actor
            # inserting a build-visible source in that audit -> vnode-registration
            # gap. The directory watcher is then armed against a directory where the
            # entry already exists, so there is no historical vnode event to drain.
            guard._watch_paths = lambda _inputs: (repo,)

            def inject_then_arm(paths, backend):
                injected.write_text('let authority = "attacker"\n', encoding="utf-8")
                return original_open_watched_inputs(paths, backend)

            guard._open_watched_inputs = inject_then_arm
            rejected = False
            try:
                try:
                    guard.run_guarded_build(
                        StableInputs(repo, accepted_sha),
                        ["/usr/bin/true"],
                        backend_factory=QuietBackend,
                        popen_factory=lambda _command: ImmediateProcess(consumed, repo),
                        require_accepted_tracked_source=True,
                    )
                except guard.BuildGuardError:
                    rejected = True
            finally:
                guard._watch_paths = original_watch_paths
                guard._open_watched_inputs = original_open_watched_inputs

            # An attacker can remove the injected source after guard teardown but
            # before the installer's outer endpoint audit. That later audit can then
            # look perfectly clean even if xcodebuild already consumed attacker bytes.
            if injected.exists():
                injected.unlink()
            endpoint_status = git(repo, "status", "--porcelain=v1", "--untracked-files=all")
            self.assertEqual(endpoint_status, "")

            if not rejected:
                self.assertIn(
                    "NembraApp/App/Injected.swift",
                    consumed,
                    "fixture must prove the compiler window observed the injected source",
                )
            self.assertTrue(
                rejected,
                "field build guard admitted an untracked build-visible source that existed before vnode registration; "
                "tracked-blob reproof cannot detect this audit-to-arm directory-entry gap",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
