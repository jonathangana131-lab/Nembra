#!/usr/bin/env python3
"""Validate whether the #2951 forged-pack primitive can reach Final-GO authority.

The original expected-red mutates a pack index created by ``git pack-objects``
without first making that read-only index writable, and assumes ordinary Git
commit/tree traversal will consume the aliased bytes. This corrected diagnostic
makes the index writable deliberately, proves the low-level alias exists when
possible, and then requires the untouched #2921 Final-GO audit to fail closed.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import stat
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
GIT = "/usr/bin/git"


def load_final_go_module():
    spec = importlib.util.spec_from_file_location("nembra_final_go_packed_tree_witness_r2", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Final-GO subject")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git_oid(object_type: bytes, payload: bytes) -> str:
    return hashlib.sha1(object_type + b" " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


class FinalGoPackedTreeWitnessR2Tests(unittest.TestCase):
    def _git(self, repo: Path, *args: str, input_bytes: bytes | None = None, check: bool = True):
        return subprocess.run(
            [GIT, "-C", str(repo), *args],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        )

    def test_forged_pack_alias_does_not_become_final_go_tree_authority(self) -> None:
        final_go = load_final_go_module()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-packed-tree-r2-") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            self._git(repo, "init", "-q")
            self._git(repo, "config", "user.email", "nembra@example.invalid")
            self._git(repo, "config", "user.name", "Nembra Final-GO Witness R2")

            product = repo / "Product.swift"
            accepted_payload = b'let authority = "accepted"\n'
            product.write_bytes(accepted_payload)
            self._git(repo, "add", "Product.swift")
            self._git(repo, "commit", "-qm", "accepted")
            accepted_source = self._git(repo, "rev-parse", "HEAD").stdout.decode("ascii").strip()

            attacker_payload = b'let authority = "attacker"\n'
            product.write_bytes(attacker_payload)
            self._git(repo, "add", "Product.swift")
            self._git(repo, "commit", "-qm", "attacker")
            attacker_commit = self._git(repo, "rev-parse", "HEAD").stdout.decode("ascii").strip()

            for relative in ("LocalSecrets", "Pods", "NembraCapture.xcworkspace"):
                (repo / relative).mkdir()
            (repo / "Podfile.lock").write_text("fixture\n", encoding="utf-8")
            self._git(repo, "update-ref", "HEAD", accepted_source)

            pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
            pack_hash = self._git(
                repo,
                "pack-objects",
                str(pack_prefix),
                input_bytes=(attacker_commit + "\n").encode("ascii"),
            ).stdout.decode("ascii").strip()
            for oid in (attacker_commit, accepted_source):
                loose = repo / ".git" / "objects" / oid[:2] / oid[2:]
                if loose.exists():
                    loose.unlink()

            index = repo / ".git" / "objects" / "pack" / f"pack-{pack_hash}.idx"
            original_mode = stat.S_IMODE(index.stat().st_mode)
            self.assertEqual(original_mode & 0o222, 0, "fixture expected pack index to start read-only")
            index.chmod(0o600)
            data = bytearray(index.read_bytes())
            self.assertEqual(data[:4], b"\xfftOc")
            self.assertEqual(struct.unpack(">I", data[4:8])[0], 2)
            fanout_offset = 8
            names_offset = fanout_offset + 256 * 4
            count = struct.unpack(">I", data[fanout_offset + 255 * 4 : fanout_offset + 256 * 4])[0]
            self.assertEqual(count, 1)
            data[names_offset : names_offset + 20] = bytes.fromhex(accepted_source)
            first_byte = int(accepted_source[:2], 16)
            for index_value in range(256):
                struct.pack_into(">I", data, fanout_offset + index_value * 4, 0 if index_value < first_byte else 1)
            data[-20:] = hashlib.sha1(data[:-20]).digest()
            index.write_bytes(data)

            # Low-level lookup may expose the aliased packed commit bytes. If it
            # does, prove they hash to the attacker commit rather than accepted.
            cat = self._git(repo, "cat-file", "commit", accepted_source, check=False)
            if cat.returncode == 0:
                actual = git_oid(b"commit", cat.stdout)
                self.assertEqual(actual, attacker_commit)
                self.assertNotEqual(actual, accepted_source)

            # Modern Git may reject the corrupt alias even before Final-GO. In
            # either case, untouched #2921 must fail closed under this primitive.
            with self.assertRaises(RuntimeError):
                final_go._audit_candidate_tree(repo, accepted_source)

            self.assertEqual(product.read_bytes(), attacker_payload)


if __name__ == "__main__":
    unittest.main(verbosity=2)
