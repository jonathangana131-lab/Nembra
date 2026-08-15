#!/usr/bin/env python3
"""Real-macOS proof that an admitted snapshot can replace live-tree ACL leases.

Run as root through sudo on macOS. The test creates one synthetic field checkout,
admits it through the accepted build-input snapshot helper, seals the copied subject
root:ephemeral-build-group with ordinary POSIX modes, and proves:
- the fresh build identity can traverse/read/execute admitted inputs;
- the fresh build identity cannot mutate the admitted snapshot;
- the invoking field identity cannot traverse the sealed snapshot at all;
- no extended ACL is required on the protected snapshot path.

This is a validation ingredient only. It does not run Xcode or create install/physical
authority.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
SNAPSHOT_PATH = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"
BUILD_ORIGIN_PATH = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SNAPSHOT = _load(SNAPSHOT_PATH, "nembra_accepted_build_input_snapshot_group_validation")
ORIGIN = _load(BUILD_ORIGIN_PATH, "nembra_build_origin_group_validation")


def _git(repo: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["/usr/bin/git", "-C", str(repo), *arguments],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(arguments)} failed: {(completed.stderr or '').strip()[-800:]}"
        )
    return (completed.stdout or "").strip()


def _chown_field_tree(root: Path, uid: int, gid: int) -> None:
    for current_raw, directory_names, file_names in os.walk(root, topdown=False, followlinks=False):
        current = Path(current_raw)
        for name in file_names:
            path = current / name
            if path.is_symlink():
                os.lchown(path, uid, gid)
            else:
                os.chown(path, uid, gid)
        for name in directory_names:
            path = current / name
            if path.is_symlink():
                os.lchown(path, uid, gid)
            else:
                os.chown(path, uid, gid)
        os.chown(current, uid, gid)


def _seal_for_build_group(parent: Path, stage: Path, gid: int) -> None:
    if parent.parent != Path("/private/tmp"):
        raise AssertionError("validation custody parent escaped /private/tmp")
    os.chown(parent, 0, gid)
    os.chmod(parent, 0o710)

    for current_raw, directory_names, file_names in os.walk(stage, topdown=False, followlinks=False):
        current = Path(current_raw)
        for name in file_names:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                os.lchown(path, 0, gid)
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise AssertionError(f"sealed snapshot contains unsupported file type: {path}")
            executable = bool(metadata.st_mode & 0o111)
            os.chown(path, 0, gid)
            os.chmod(path, 0o750 if executable else 0o640)
        for name in directory_names:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                os.lchown(path, 0, gid)
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                raise AssertionError(f"sealed snapshot contains unsupported directory type: {path}")
            os.chown(path, 0, gid)
            os.chmod(path, 0o750)
        os.chown(current, 0, gid)
        os.chmod(current, 0o750)


def _acl_lines(path: Path) -> tuple[str, ...]:
    completed = subprocess.run(
        ["/bin/ls", "-lde", str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(f"could not inspect ACL state for {path}: {completed.stderr}")
    return tuple(
        line
        for line in (completed.stdout or "").splitlines()[1:]
        if re.match(r"^\s*\d+:\s", line)
    )


def _run_as(
    uid: int,
    gid: int,
    groups: tuple[int, ...],
    argv: list[str],
    *,
    cwd: Path,
) -> subprocess.CompletedProcess[str]:
    environment = {
        "HOME": "/var/empty",
        "USER": str(uid),
        "LOGNAME": str(uid),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "C",
        "LC_ALL": "C",
    }
    return subprocess.run(
        argv,
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **ORIGIN._structured_credentials(uid, gid, groups),
    )


class CaptureAcceptedSnapshotBuildGroupNoACLTests(unittest.TestCase):
    def test_root_sealed_snapshot_replaces_live_field_tree_acl_lease(self) -> None:
        if sys.platform != "darwin" or os.geteuid() != 0:
            self.skipTest("requires root on macOS")

        field_name, field_uid, field_gid, _field_home, field_groups = ORIGIN._invoking_identity()
        self.assertGreater(field_uid, 0)
        self.assertNotEqual(field_name, "root")

        field_root = Path(tempfile.mkdtemp(prefix="nembra-snapshot-field.", dir="/private/tmp"))
        custody_parent = Path(tempfile.mkdtemp(prefix="nembra-snapshot-custody.", dir="/private/tmp"))
        stage = custody_parent / "accepted-build-inputs"
        build_name = f"nembrasnap{os.getpid()}"
        build_id: int | None = None
        try:
            # Minimal tracked source plus all five generated/private manifest subjects.
            _git(field_root, "init", "-q")
            _git(field_root, "config", "user.name", "Nembra Validation")
            _git(field_root, "config", "user.email", "validation@nembra.invalid")
            (field_root / ".gitignore").write_text(
                "Podfile.lock\nPods/\nNembraCapture.xcworkspace/\nLocalSecrets/\n",
                encoding="utf-8",
            )
            tracked = field_root / "Sources/tracked.txt"
            tracked.parent.mkdir(parents=True)
            tracked.write_text("accepted tracked source\n", encoding="utf-8")
            executable = field_root / "Scripts/read-marker.sh"
            executable.parent.mkdir(parents=True)
            executable.write_text("#!/bin/sh\nprintf 'snapshot-exec-ok\\n'\n", encoding="utf-8")
            executable.chmod(0o755)
            _git(field_root, "add", ".gitignore", "Sources/tracked.txt", "Scripts/read-marker.sh")
            _git(field_root, "commit", "-q", "-m", "synthetic accepted source")
            source_sha = _git(field_root, "rev-parse", "HEAD").lower()
            self.assertRegex(source_sha, r"^[0-9a-f]{40}$")

            generated = {
                "Podfile.lock": "PODS:\n  - Fixture\n",
                "NembraCapture.xcworkspace/contents.xcworkspacedata": "<Workspace/>\n",
                "Pods/Fixture/libfixture.a": "synthetic pod bytes\n",
                "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec": "Pod::Spec.new {}\n",
                "LocalSecrets/TuyaSDK/Build/private-sdk.bin": "private sdk fixture\n",
                "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec": "Pod::Spec.new {}\n",
                "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Config.swift": "let fixture = true\n",
            }
            for relative, content in generated.items():
                path = field_root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")

            # Make the mutable candidate genuinely field-owned before root admission.
            _chown_field_tree(field_root, field_uid, field_gid)
            manifest = SNAPSHOT.generated_manifest_sha256(field_root, source_sha)
            self.assertRegex(manifest, r"^[0-9a-f]{64}$")
            actual = SNAPSHOT.stage_accepted_build_inputs(
                field_root,
                source_sha,
                stage,
                manifest,
            )
            self.assertEqual(actual, manifest)

            build_id = ORIGIN._choose_ephemeral_id()
            ORIGIN._create_local_build_identity(build_name, build_id, build_id, Path("/var/empty"))
            baseline = tuple(sorted(set(os.getgrouplist(build_name, build_id))))
            self.assertIn(build_id, baseline)
            self.assertFalse(set(field_groups).difference(baseline).intersection(baseline))

            _seal_for_build_group(custody_parent, stage, build_id)
            self.assertEqual(_acl_lines(custody_parent), ())
            self.assertEqual(_acl_lines(stage), ())
            self.assertEqual(_acl_lines(stage / "LocalSecrets"), ())

            read_probe = _run_as(
                build_id,
                build_id,
                (),
                [
                    "/usr/bin/python3",
                    "-B",
                    "-I",
                    "-c",
                    (
                        "from pathlib import Path;"
                        "assert Path('Sources/tracked.txt').read_text()=='accepted tracked source\\n';"
                        "assert 'private sdk fixture' in Path('LocalSecrets/TuyaSDK/Build/private-sdk.bin').read_text();"
                        "assert 'synthetic pod bytes' in Path('Pods/Fixture/libfixture.a').read_text();"
                        "print('snapshot-read-ok')"
                    ),
                ],
                cwd=stage,
            )
            self.assertEqual(read_probe.returncode, 0, read_probe.stderr)
            self.assertIn("snapshot-read-ok", read_probe.stdout)

            exec_probe = _run_as(
                build_id,
                build_id,
                (),
                [str(stage / "Scripts/read-marker.sh")],
                cwd=stage,
            )
            self.assertEqual(exec_probe.returncode, 0, exec_probe.stderr)
            self.assertEqual(exec_probe.stdout.strip(), "snapshot-exec-ok")

            mutate_probe = _run_as(
                build_id,
                build_id,
                (),
                [
                    "/usr/bin/python3",
                    "-B",
                    "-I",
                    "-c",
                    "from pathlib import Path; Path('Sources/tracked.txt').write_text('mutated')",
                ],
                cwd=stage,
            )
            self.assertNotEqual(mutate_probe.returncode, 0)
            create_probe = _run_as(
                build_id,
                build_id,
                (),
                [
                    "/usr/bin/python3",
                    "-B",
                    "-I",
                    "-c",
                    "from pathlib import Path; Path('new-file').write_text('nope')",
                ],
                cwd=stage,
            )
            self.assertNotEqual(create_probe.returncode, 0)
            self.assertEqual((stage / "Sources/tracked.txt").read_text(), "accepted tracked source\n")
            self.assertFalse((stage / "new-file").exists())

            # The invoking field identity cannot even traverse the root/build-group custody parent.
            field_probe = _run_as(
                field_uid,
                field_gid,
                field_groups,
                ["/bin/cat", str(stage / "Sources/tracked.txt")],
                cwd=Path("/private/tmp"),
            )
            self.assertNotEqual(field_probe.returncode, 0)

            # The admitted manifest remains exactly the accepted one after build-identity reads.
            self.assertEqual(SNAPSHOT.generated_manifest_sha256(stage, source_sha), manifest)
        finally:
            if build_id is not None:
                ORIGIN._remove_local_build_identity(build_name, build_id, require_absent=True)
            shutil.rmtree(custody_parent, ignore_errors=True)
            shutil.rmtree(field_root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
