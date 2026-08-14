#!/usr/bin/env python3
"""Real macOS witness for the scoped dedicated-build-UID private read lease."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"
BUILD_ORIGIN = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateBuildUIDReadLeaseTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin" and os.geteuid() == 0, "requires root on macOS")
    def test_read_and_internal_symlink_exist_only_during_lease_while_mutation_stays_denied(self) -> None:
        orchestrator = load(ORCHESTRATOR, "nembra_private_read_lease_orchestrator")
        origin = load(BUILD_ORIGIN, "nembra_private_read_lease_build_origin")
        uid = origin._choose_ephemeral_id()
        gid = uid
        name = f"nembrabuildlease{os.getpid()}"
        private_tmp = origin._require_real_private_tmp()
        workspace = Path(tempfile.mkdtemp(prefix="nembra-private-read-lease.", dir=private_tmp))
        home = workspace / "home"
        repo = workspace / "repo"
        build_root = repo / "LocalSecrets/TuyaSDK/Build"
        payload = build_root / "payload.bin"
        alias = build_root / "payload-link.bin"
        created_identity = False
        lease = None
        try:
            home.mkdir()
            build_root.mkdir(parents=True)
            payload.write_bytes(b"accepted-private-payload\n")
            alias.symlink_to("payload.bin")
            for directory in (repo, repo / "LocalSecrets", repo / "LocalSecrets/TuyaSDK", build_root):
                directory.chmod(0o700)
            payload.chmod(0o600)
            origin._create_local_build_identity(name, uid, gid, home)
            created_identity = True

            def as_build(code: str, *args: str):
                return subprocess.run(
                    ["/usr/bin/python3", "-I", "-c", code, *args],
                    user=uid,
                    group=gid,
                    extra_groups=[],
                    cwd="/",
                    env={"PATH": "/usr/bin:/bin", "HOME": str(home), "LANG": "C", "LC_ALL": "C"},
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                )

            read_code = "from pathlib import Path; import sys; sys.stdout.buffer.write(Path(sys.argv[1]).read_bytes())"
            write_code = "from pathlib import Path; import sys; Path(sys.argv[1]).write_bytes(b'substituted')"

            self.assertNotEqual(as_build(read_code, str(payload)).returncode, 0)
            self.assertNotEqual(as_build(read_code, str(alias)).returncode, 0)

            lease = orchestrator._PrivateReadLease((build_root,), repo)
            lease.grant(name)
            direct = as_build(read_code, str(payload))
            linked = as_build(read_code, str(alias))
            self.assertEqual(direct.returncode, 0, direct.stderr)
            self.assertEqual(direct.stdout.encode(), b"accepted-private-payload\n")
            self.assertEqual(linked.returncode, 0, linked.stderr)
            self.assertEqual(linked.stdout.encode(), b"accepted-private-payload\n")
            self.assertNotEqual(as_build(write_code, str(payload)).returncode, 0)
            chmod_attempt = subprocess.run(
                ["/bin/chmod", "0644", str(payload)],
                user=uid,
                group=gid,
                extra_groups=[],
                cwd="/",
                env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            self.assertNotEqual(chmod_attempt.returncode, 0)
            self.assertEqual(payload.read_bytes(), b"accepted-private-payload\n")
            self.assertEqual(payload.stat().st_mode & 0o777, 0o600)

            lease.revoke()
            lease = None
            self.assertNotEqual(as_build(read_code, str(payload)).returncode, 0)
            self.assertNotEqual(as_build(read_code, str(alias)).returncode, 0)
        finally:
            if lease is not None:
                lease.revoke(suppress_errors=True)
            if created_identity:
                origin._remove_local_build_identity(name, uid, require_absent=True)
            try:
                workspace.chmod(0o700)
            except OSError:
                pass
            shutil.rmtree(workspace, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
