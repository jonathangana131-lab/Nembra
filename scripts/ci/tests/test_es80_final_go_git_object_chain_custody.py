#!/usr/bin/env python3
"""Mechanical pack-index attacks against Final-GO accepted object-chain custody."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
GIT = "/usr/bin/git"
TARGET = "Scripts/bootstrap_capture_tuya_sdk.sh"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_object_chain", PRIVATE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load current Final-GO candidate authority")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def object_oid(object_type: str, payload: bytes) -> str:
    return hashlib.sha1(
        object_type.encode("ascii")
        + b" "
        + str(len(payload)).encode("ascii")
        + b"\0"
        + payload
    ).hexdigest()


class FinalGoGitObjectChainCustodyTests(unittest.TestCase):
    def _git(self, repo: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
        return subprocess.check_output(
            [GIT, "-C", str(repo), *args], input=input_bytes, stderr=subprocess.DEVNULL
        )

    def _repository(self, repo: Path):
        repo.mkdir(parents=True)
        subprocess.run([GIT, "init", "-q", str(repo)], check=True)
        subprocess.run([GIT, "-C", str(repo), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run([GIT, "-C", str(repo), "config", "user.name", "Nembra Capture QA"], check=True)
        path = repo / TARGET
        path.parent.mkdir(parents=True)
        accepted_payload = b"#!/bin/bash\necho accepted-bootstrap\n"
        path.write_bytes(accepted_payload)
        path.chmod(0o755)
        subprocess.run([GIT, "-C", str(repo), "add", TARGET], check=True)
        subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "accepted"], check=True)
        accepted_commit = self._git(repo, "rev-parse", "HEAD").decode().strip()
        accepted_tree = self._git(repo, "rev-parse", "HEAD^{tree}").decode().strip()
        accepted_blob = self._git(repo, "rev-parse", f"HEAD:{TARGET}").decode().strip()
        self.assertEqual(object_oid("commit", self._git(repo, "cat-file", "commit", accepted_commit)), accepted_commit)
        self.assertEqual(object_oid("tree", self._git(repo, "cat-file", "tree", accepted_tree)), accepted_tree)
        self.assertEqual(object_oid("blob", accepted_payload), accepted_blob)

        attacker_payload = b"#!/bin/bash\necho attacker-executed\n"
        path.write_bytes(attacker_payload)
        subprocess.run([GIT, "-C", str(repo), "add", TARGET], check=True)
        subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "attacker"], check=True)
        attacker_commit = self._git(repo, "rev-parse", "HEAD").decode().strip()
        attacker_tree = self._git(repo, "rev-parse", "HEAD^{tree}").decode().strip()
        subprocess.run([GIT, "-C", str(repo), "reset", "--hard", "-q", accepted_commit], check=True)
        self.assertEqual(path.read_bytes(), accepted_payload)
        return accepted_commit, accepted_tree, accepted_blob, attacker_commit, attacker_tree, attacker_payload

    def _forge_alias(self, repo: Path, *, source_oid: str, alias_oid: str) -> Path:
        pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
        pack_hash = subprocess.check_output(
            [GIT, "-C", str(repo), "pack-objects", str(pack_prefix)],
            input=(source_oid + "\n").encode("ascii"),
        ).decode().strip()
        for oid in (source_oid, alias_oid):
            loose = repo / ".git" / "objects" / oid[:2] / oid[2:]
            if loose.exists():
                loose.unlink()
        index = repo / ".git" / "objects" / "pack" / f"pack-{pack_hash}.idx"
        data = bytearray(index.read_bytes())
        self.assertEqual(data[:4], b"\xfftOc")
        self.assertEqual(struct.unpack(">I", data[4:8])[0], 2)
        fanout = 8
        names = fanout + 256 * 4
        count = struct.unpack(">I", data[fanout + 255 * 4 : fanout + 256 * 4])[0]
        self.assertEqual(count, 1)
        data[names : names + 20] = bytes.fromhex(alias_oid)
        first = int(alias_oid[:2], 16)
        for value in range(256):
            struct.pack_into(">I", data, fanout + value * 4, 0 if value < first else 1)
        data[-20:] = hashlib.sha1(data[:-20]).digest()
        index.write_bytes(data)
        return index

    def test_forged_commit_name_cannot_retarget_tree_authority(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-commit-chain-") as directory:
            repo = Path(directory) / "repo"
            accepted_commit, _, accepted_blob, attacker_commit, _, attacker_payload = self._repository(repo)
            baseline = MODULE._tree_entries(repo, accepted_commit)
            self.assertEqual(baseline[TARGET][1], accepted_blob)
            forged = self._forge_alias(repo, source_oid=attacker_commit, alias_oid=accepted_commit)
            substituted = self._git(repo, "cat-file", "commit", accepted_commit)
            self.assertNotEqual(object_oid("commit", substituted), accepted_commit)
            ambient = self._git(repo, "ls-tree", "-r", "-z", accepted_commit)
            self.assertIn(object_oid("blob", attacker_payload).encode("ascii"), ambient)
            with self.assertRaises(RuntimeError):
                MODULE._tree_entries(repo, accepted_commit)
            verify = subprocess.run([GIT, "verify-pack", "-v", str(forged)], check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(verify.returncode, 0)

    def test_forged_tree_name_cannot_retarget_leaf_authority(self):
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-tree-chain-") as directory:
            repo = Path(directory) / "repo"
            accepted_commit, accepted_tree, accepted_blob, _, attacker_tree, attacker_payload = self._repository(repo)
            self.assertEqual(MODULE._tree_entries(repo, accepted_commit)[TARGET][1], accepted_blob)
            forged = self._forge_alias(repo, source_oid=attacker_tree, alias_oid=accepted_tree)
            substituted = self._git(repo, "cat-file", "tree", accepted_tree)
            self.assertNotEqual(object_oid("tree", substituted), accepted_tree)
            self.assertIn(object_oid("blob", attacker_payload).encode("ascii"), self._git(repo, "ls-tree", accepted_tree))
            with self.assertRaises(RuntimeError):
                MODULE._tree_entries(repo, accepted_commit)
            verify = subprocess.run([GIT, "verify-pack", "-v", str(forged)], check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(verify.returncode, 0)

    def test_tree_authority_never_delegates_to_ls_tree(self):
        source = PRIVATE.read_text(encoding="utf-8")
        body = source.split("def _tree_entries", 1)[1].split("def _stable_stat", 1)[0]
        self.assertNotIn('"ls-tree"', body)
        self.assertIn('_verified_object_bytes(root, "commit", source', body)
        self.assertIn('_verified_object_bytes(', body)
        self.assertIn('root, "tree", tree_oid', body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
