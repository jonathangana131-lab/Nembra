#!/usr/bin/env python3
"""Real-macOS validation for root-custodied accepted Capture build inputs.

Synthetic public/private fixture bytes only. The witness proves that exact-Git +
preaccepted generated inputs can be admitted into a root-only container, remain
unchanged after the real field identity mutates the live checkout, and deny the
field identity read/write authority to the sealed build root.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
from types import ModuleType
import unittest


class ValidationError(RuntimeError):
    pass


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve()
CI = HERE.parents[1]
custody = _load(CI / "capture_accepted_build_root_custody.py", "nembra_build_root_custody_test")
snapshot = custody.snapshot


def git(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["/usr/bin/git", "-C", str(repo), *args],
        env={
            "HOME": "/var/empty",
            "PATH": "/usr/bin:/bin",
            "LANG": "C",
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
        },
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise ValidationError(f"git fixture command failed: {completed.stderr[-800:]!r}")
    return completed.stdout.strip()


def seed_repo(root: Path) -> str:
    git(root, "init", "-q")
    git(root, "config", "user.email", "capture-root-custody@example.invalid")
    git(root, "config", "user.name", "Capture Root Custody")
    (root / "Sources").mkdir()
    (root / "Sources/App.swift").write_text("let acceptedTracked = true\n", encoding="utf-8")
    (root / "NembraCapture.xcodeproj").mkdir()
    (root / "NembraCapture.xcodeproj/project.pbxproj").write_text("// accepted project\n", encoding="utf-8")
    git(root, "add", "Sources", "NembraCapture.xcodeproj")
    git(root, "commit", "-qm", "accepted tracked source")
    return git(root, "rev-parse", "HEAD")


def seed_generated(root: Path) -> None:
    (root / "Podfile.lock").write_text("PODS:\n  - Fixture (1.0)\n", encoding="utf-8")

    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")

    pods = root / "Pods/Fixture"
    pods.mkdir(parents=True)
    (pods / "libFixture.a").write_bytes(b"generated-pod-fixture")

    sdk = root / "LocalSecrets/TuyaSDK/Build"
    sdk.mkdir(parents=True)
    (sdk.parent / "ThingSmartCryption.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sdk / "libThingSmartCryption.a").write_bytes(b"private-sdk-fixture")

    runtime = root / "LocalSecrets/TuyaRuntime"
    runtime_sources = runtime / "Sources/NembraTuyaPrivateConfig"
    runtime_sources.mkdir(parents=True)
    (runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (runtime_sources / "Identity.swift").write_text(
        'let syntheticSecret = "ACCEPTED-PRIVATE-A"\n',
        encoding="utf-8",
    )
    (runtime / "ResolvedTuyaDependencyProvenance.txt").write_text(
        "schema=1\nsynthetic-private-hashes-only\n",
        encoding="utf-8",
    )


def chown_tree(root: Path, uid: int, gid: int) -> None:
    for current_raw, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_raw)
        os.chown(current, uid, gid)
        os.chmod(current, 0o755)
        for name in list(directory_names):
            candidate = current / name
            if candidate.is_symlink():
                directory_names.remove(name)
                os.lchown(candidate, uid, gid)
        for name in file_names:
            candidate = current / name
            if candidate.is_symlink():
                os.lchown(candidate, uid, gid)
            else:
                os.chown(candidate, uid, gid)
                os.chmod(candidate, 0o644)


def field_run(
    field: pwd.struct_passwd,
    groups: tuple[int, ...],
    source: str,
    *paths: Path,
) -> subprocess.CompletedProcess[str]:
    def demote() -> None:
        os.setgroups(list(groups))
        os.setgid(field.pw_gid)
        os.setuid(field.pw_uid)

    return subprocess.run(
        ["/usr/bin/python3", "-I", "-c", source, *[str(path) for path in paths]],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        preexec_fn=demote,
    )


def require_permission_denied(completed: subprocess.CompletedProcess[str], label: str) -> None:
    if completed.returncode == 0:
        raise AssertionError(f"{label} unexpectedly succeeded")
    detail = (completed.stderr or "")[-1200:]
    if "PermissionError" not in detail and "Permission denied" not in detail:
        raise AssertionError(f"{label} failed for a non-permission reason: {detail!r}")


class AcceptedBuildRootCustodyTests(unittest.TestCase):
    field: pwd.struct_passwd
    field_groups: tuple[int, ...]

    @classmethod
    def setUpClass(cls) -> None:
        if sys.platform != "darwin" or os.geteuid() != 0:
            raise ValidationError("accepted build-root custody validation requires root on real macOS")
        raw_field = os.environ.get("NEMBRA_TEST_FIELD_USER", "")
        if not raw_field:
            raise ValidationError("NEMBRA_TEST_FIELD_USER is required")
        cls.field = pwd.getpwnam(raw_field)
        if cls.field.pw_uid <= 0 or cls.field.pw_gid <= 0:
            raise ValidationError("field test identity must be a non-root local account")
        cls.field_groups = tuple(sorted(set(os.getgrouplist(cls.field.pw_name, cls.field.pw_gid))))
        if any(group < 0 for group in cls.field_groups):
            raise ValidationError("field group vector is invalid")

    def setUp(self) -> None:
        self.test_root = Path(tempfile.mkdtemp(prefix="nembra-build-root-custody-test.", dir="/private/tmp"))
        os.chown(self.test_root, 0, 0)
        os.chmod(self.test_root, 0o755)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_root, ignore_errors=True)

    def _fixture(self) -> tuple[Path, str, str]:
        repo = self.test_root / "field-repo"
        repo.mkdir()
        source_sha = seed_repo(repo)
        seed_generated(repo)
        accepted_manifest = snapshot.generated_manifest_sha256(repo, source_sha)
        chown_tree(repo, self.field.pw_uid, self.field.pw_gid)
        return repo, source_sha, accepted_manifest

    def _custody_parent(self, name: str) -> Path:
        parent = self.test_root / name
        parent.mkdir(mode=0o700)
        os.chown(parent, 0, 0)
        os.chmod(parent, 0o700)
        return parent

    def test_root_custody_freezes_admitted_inputs_against_field_checkout_mutation(self) -> None:
        repo, source_sha, accepted_manifest = self._fixture()
        parent = self._custody_parent("custody")
        accepted_root, fingerprint, returned_manifest = custody.create_accepted_build_root(
            repo,
            source_sha,
            accepted_manifest,
            parent=parent,
        )

        self.assertEqual(returned_manifest, accepted_manifest)
        self.assertEqual(custody.accepted_build_root_fingerprint(accepted_root), fingerprint)
        self.assertEqual(accepted_root.parent.stat().st_uid, 0)
        self.assertEqual(stat.S_IMODE(accepted_root.parent.stat().st_mode), 0o700)
        self.assertEqual(accepted_root.stat().st_uid, 0)
        self.assertEqual(stat.S_IMODE(accepted_root.stat().st_mode), 0o700)

        staged_tracked = accepted_root / "Sources/App.swift"
        staged_private = (
            accepted_root
            / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Identity.swift"
        )
        self.assertEqual(staged_tracked.read_text(encoding="utf-8"), "let acceptedTracked = true\n")
        self.assertIn("ACCEPTED-PRIVATE-A", staged_private.read_text(encoding="utf-8"))
        self.assertEqual(stat.S_IMODE(staged_private.stat().st_mode), 0o600)
        self.assertEqual(staged_private.stat().st_uid, 0)

        live_tracked = repo / "Sources/App.swift"
        live_private = repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Identity.swift"
        attack = field_run(
            self.field,
            self.field_groups,
            (
                "from pathlib import Path; import sys; "
                "Path(sys.argv[1]).write_text('let attackedTracked = true\\n'); "
                "Path(sys.argv[2]).write_text('let syntheticSecret = \\\"MUTATED-PRIVATE-B\\\"\\n')"
            ),
            live_tracked,
            live_private,
        )
        self.assertEqual(attack.returncode, 0, attack.stderr)
        self.assertIn("attackedTracked", live_tracked.read_text(encoding="utf-8"))
        self.assertIn("MUTATED-PRIVATE-B", live_private.read_text(encoding="utf-8"))

        self.assertEqual(custody.accepted_build_root_fingerprint(accepted_root), fingerprint)
        self.assertEqual(staged_tracked.read_text(encoding="utf-8"), "let acceptedTracked = true\n")
        self.assertIn("ACCEPTED-PRIVATE-A", staged_private.read_text(encoding="utf-8"))
        self.assertEqual(snapshot.generated_manifest_sha256(accepted_root, source_sha), accepted_manifest)

        field_read = field_run(
            self.field,
            self.field_groups,
            "from pathlib import Path; import sys; print(Path(sys.argv[1]).read_text())",
            staged_private,
        )
        require_permission_denied(field_read, "field read against sealed private input")

        field_write = field_run(
            self.field,
            self.field_groups,
            "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('attack\\n')",
            staged_tracked,
        )
        require_permission_denied(field_write, "field write against sealed tracked input")
        self.assertEqual(custody.accepted_build_root_fingerprint(accepted_root), fingerprint)

    def test_bad_manifest_fails_closed_without_leaving_candidate(self) -> None:
        repo, source_sha, _accepted_manifest = self._fixture()
        parent = self._custody_parent("failed-custody")
        with self.assertRaises(snapshot.AcceptedBuildInputSnapshotError):
            custody.create_accepted_build_root(
                repo,
                source_sha,
                "0" * 64,
                parent=parent,
            )
        self.assertEqual(list(parent.iterdir()), [])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field-user", required=True)
    args, remaining = parser.parse_known_args()
    os.environ["NEMBRA_TEST_FIELD_USER"] = args.field_user
    if remaining:
        raise ValidationError(f"unexpected test arguments: {remaining!r}")
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AcceptedBuildRootCustodyTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
