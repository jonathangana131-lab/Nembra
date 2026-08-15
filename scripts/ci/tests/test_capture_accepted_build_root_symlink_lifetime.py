#!/usr/bin/env python3
"""Real-macOS witness that root custody closes field symlink lifetime retargeting."""
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
custody = _load(CI / "capture_accepted_build_root_custody.py", "nembra_root_symlink_lifetime")
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
    git(root, "config", "user.email", "capture-symlink-lifetime@example.invalid")
    git(root, "config", "user.name", "Capture Symlink Lifetime")
    (root / "Sources").mkdir()
    (root / "Sources/App.swift").write_text("let acceptedTracked = true\n", encoding="utf-8")
    (root / "NembraCapture.xcodeproj").mkdir()
    (root / "NembraCapture.xcodeproj/project.pbxproj").write_text("// accepted project\n", encoding="utf-8")
    git(root, "add", "Sources", "NembraCapture.xcodeproj")
    git(root, "commit", "-qm", "accepted tracked source")
    return git(root, "rev-parse", "HEAD")


def seed_generated(root: Path) -> Path:
    (root / "Podfile.lock").write_text("PODS:\n  - Fixture (1.0)\n", encoding="utf-8")
    workspace = root / "NembraCapture.xcworkspace"
    workspace.mkdir()
    (workspace / "contents.xcworkspacedata").write_text("<Workspace/>\n", encoding="utf-8")

    pods = root / "Pods/Fixture"
    pods.mkdir(parents=True)
    (pods / "inside.txt").write_text("ACCEPTED-INTERNAL\n", encoding="utf-8")
    live_link = pods / "current"
    live_link.symlink_to("inside.txt")

    sdk = root / "LocalSecrets/TuyaSDK/Build"
    sdk.mkdir(parents=True)
    (sdk.parent / "ThingSmartCryption.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (sdk / "libThingSmartCryption.a").write_bytes(b"private-sdk-fixture")

    runtime_sources = root / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
    runtime_sources.mkdir(parents=True)
    runtime = root / "LocalSecrets/TuyaRuntime"
    (runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new\n", encoding="utf-8")
    (runtime_sources / "Identity.swift").write_text(
        'let syntheticSecret = "ACCEPTED-PRIVATE-A"\n', encoding="utf-8"
    )
    (runtime / "ResolvedTuyaDependencyProvenance.txt").write_text(
        "schema=1\nsynthetic-private-hashes-only\n", encoding="utf-8"
    )
    return live_link


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


def field_run(field: pwd.struct_passwd, groups: tuple[int, ...], source: str, *paths: Path) -> subprocess.CompletedProcess[str]:
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


class AcceptedBuildRootSymlinkLifetimeTests(unittest.TestCase):
    field: pwd.struct_passwd
    field_groups: tuple[int, ...]

    @classmethod
    def setUpClass(cls) -> None:
        if sys.platform != "darwin" or os.geteuid() != 0:
            raise ValidationError("accepted build-root symlink lifetime validation requires root on macOS")
        raw_field = os.environ.get("NEMBRA_TEST_FIELD_USER", "")
        if not raw_field:
            raise ValidationError("NEMBRA_TEST_FIELD_USER is required")
        cls.field = pwd.getpwnam(raw_field)
        if cls.field.pw_uid <= 0 or cls.field.pw_gid <= 0:
            raise ValidationError("field witness must be a non-root local account")
        cls.field_groups = tuple(sorted(set(os.getgrouplist(cls.field.pw_name, cls.field.pw_gid))))

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="nembra-root-symlink-lifetime.", dir="/private/tmp"))
        os.chown(self.root, 0, 0)
        os.chmod(self.root, 0o755)

    def tearDown(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)

    def test_field_can_retarget_live_link_but_not_sealed_accepted_link(self) -> None:
        repo = self.root / "field-repo"
        repo.mkdir()
        source_sha = seed_repo(repo)
        live_link = seed_generated(repo)
        accepted_manifest = snapshot.generated_manifest_sha256(repo, source_sha)
        chown_tree(repo, self.field.pw_uid, self.field.pw_gid)

        parent = self.root / "custody"
        parent.mkdir(mode=0o700)
        os.chown(parent, 0, 0)
        os.chmod(parent, 0o700)
        accepted_root, fingerprint, returned_manifest = custody.create_accepted_build_root(
            repo, source_sha, accepted_manifest, parent=parent
        )
        self.assertEqual(returned_manifest, accepted_manifest)

        staged_link = accepted_root / "Pods/Fixture/current"
        self.assertTrue(staged_link.is_symlink())
        self.assertEqual(os.readlink(staged_link), "inside.txt")
        self.assertEqual(staged_link.read_text(encoding="utf-8"), "ACCEPTED-INTERNAL\n")
        staged_metadata = staged_link.lstat()
        self.assertEqual(staged_metadata.st_uid, 0)
        self.assertEqual(staged_metadata.st_gid, 0)

        external = self.root / "field-external.txt"
        external.write_text("EXTERNAL-ATTACK\n", encoding="utf-8")
        os.chown(external, self.field.pw_uid, self.field.pw_gid)
        os.chmod(external, 0o644)
        retarget = (
            "from pathlib import Path; import sys; "
            "link=Path(sys.argv[1]); link.unlink(); link.symlink_to(sys.argv[2])"
        )

        live_attack = field_run(self.field, self.field_groups, retarget, live_link, external)
        self.assertEqual(live_attack.returncode, 0, live_attack.stderr)
        self.assertEqual(os.readlink(live_link), str(external))
        self.assertEqual(live_link.read_text(encoding="utf-8"), "EXTERNAL-ATTACK\n")

        sealed_attack = field_run(self.field, self.field_groups, retarget, staged_link, external)
        require_permission_denied(sealed_attack, "field retarget against sealed accepted symlink")
        self.assertEqual(os.readlink(staged_link), "inside.txt")
        self.assertEqual(staged_link.read_text(encoding="utf-8"), "ACCEPTED-INTERNAL\n")
        self.assertEqual(custody.accepted_build_root_fingerprint(accepted_root), fingerprint)
        self.assertEqual(snapshot.generated_manifest_sha256(accepted_root, source_sha), accepted_manifest)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field-user", required=True)
    args, remaining = parser.parse_known_args()
    os.environ["NEMBRA_TEST_FIELD_USER"] = args.field_user
    if remaining:
        raise ValidationError(f"unexpected test arguments: {remaining!r}")
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AcceptedBuildRootSymlinkLifetimeTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
