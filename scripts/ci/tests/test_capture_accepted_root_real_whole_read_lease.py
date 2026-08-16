#!/usr/bin/env python3
"""Real Darwin witness for ephemeral complete accepted-root compiler authority."""
from __future__ import annotations
import argparse
import importlib.util
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"

def load():
    spec = importlib.util.spec_from_file_location("nembra_real_whole_root_lease", ORCHESTRATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def field_run(field, groups, source: str, *paths: Path):
    extras = sorted({int(group) for group in groups if int(group) != field.pw_gid and int(group) > 0})
    return subprocess.run(
        ["/usr/bin/python3", "-I", "-c", source, *[str(path) for path in paths]],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        user=field.pw_uid,
        group=field.pw_gid,
        extra_groups=extras,
    )

def seed(root: Path):
    (root / "NembraCapture.xcworkspace").mkdir(parents=True)
    (root / "NembraCapture.xcworkspace/contents.xcworkspacedata").write_text("<Workspace/>\n")
    (root / "Pods/FrameworkA").mkdir(parents=True)
    (root / "Pods/FrameworkA/module.bin").write_bytes(b"module")
    (root / "Pods/FrameworkCurrent").symlink_to("FrameworkA", target_is_directory=True)
    (root / "Sources").mkdir()
    (root / "Sources/App.swift").write_text("let accepted = true\n")
    (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
    (root / "LocalSecrets/TuyaSDK/sdk.bin").write_bytes(b"sdk")
    (root / "LocalSecrets/TuyaRuntime").mkdir(parents=True)
    (root / "LocalSecrets/TuyaRuntime/runtime.bin").write_bytes(b"runtime")
    (root / "Podfile.lock").write_text("PODS:\n")
    for current_raw, directories, files in os.walk(root, followlinks=False):
        current = Path(current_raw)
        os.chown(current, 0, 0)
        os.chmod(current, 0o700)
        for name in directories:
            candidate = current / name
            if candidate.is_symlink():
                os.lchown(candidate, 0, 0)
        for name in files:
            candidate = current / name
            if candidate.is_symlink():
                os.lchown(candidate, 0, 0)
            else:
                os.chown(candidate, 0, 0)
                os.chmod(candidate, 0o600)

class RealWholeRootLeaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != "darwin" or os.geteuid() != 0:
            raise RuntimeError("real whole-root lease witness requires root on Darwin")
        cls.field = pwd.getpwnam(os.environ["NEMBRA_TEST_FIELD_USER"])
        cls.groups = tuple(os.getgrouplist(cls.field.pw_name, cls.field.pw_gid))

    def setUp(self):
        self.outer = Path(tempfile.mkdtemp(prefix="nembra-real-whole-root-", dir="/private/tmp"))
        os.chown(self.outer, 0, 0)
        os.chmod(self.outer, 0o700)

    def tearDown(self):
        shutil.rmtree(self.outer, ignore_errors=True)

    def test_complete_root_is_readable_only_during_lease(self):
        helper = load()
        root = self.outer / "accepted"
        root.mkdir(mode=0o700)
        seed(root)
        targets = (
            root / "Podfile.lock",
            root / "NembraCapture.xcworkspace/contents.xcworkspacedata",
            root / "Pods/FrameworkCurrent/module.bin",
            root / "Sources/App.swift",
            root / "LocalSecrets/TuyaSDK/sdk.bin",
            root / "LocalSecrets/TuyaRuntime/runtime.bin",
        )
        probe = "from pathlib import Path; import sys; [Path(p).read_bytes() for p in sys.argv[1:]]"
        before = field_run(self.field, self.groups, probe, *targets)
        self.assertNotEqual(before.returncode, 0)

        lease = helper._PrivateReadLease((root,), root)
        lease.grant(self.field.pw_name)
        try:
            during = field_run(self.field, self.groups, probe, *targets)
            self.assertEqual(during.returncode, 0, during.stderr)
        finally:
            lease.revoke()

        self.assertFalse(lease._opened)
        self.assertEqual(lease._principal, "")
        after = field_run(self.field, self.groups, probe, *targets)
        self.assertNotEqual(after.returncode, 0)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--field-user", required=True)
    args = parser.parse_args()
    os.environ["NEMBRA_TEST_FIELD_USER"] = args.field_user
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(RealWholeRootLeaseTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1

if __name__ == "__main__":
    raise SystemExit(main())
