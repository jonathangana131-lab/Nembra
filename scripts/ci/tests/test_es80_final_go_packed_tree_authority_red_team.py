#!/usr/bin/env python3
"""Expected-red witness for Final-GO accepted-tree object authority.

Final-GO correctly compares raw physical files to blob OIDs emitted by its
accepted-tree traversal. That traversal must itself be bound to the externally
accepted commit/tree bytes. A same-UID actor who can mutate the local Git object
database can forge a pack index so lookup of the accepted commit OID returns a
different packed commit. Ordinary ``git ls-tree <accepted-source>`` then emits
the attacker's tree/blob mapping while the symbolic HEAD still names the exact
accepted source. If Final-GO trusts that mapping without independently hashing
the returned commit/tree object bytes, an attacker-controlled physical tree can
be admitted as though it were the accepted candidate.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
GIT = "/usr/bin/git"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


def load_final_go_module():
    spec = importlib.util.spec_from_file_location("nembra_final_go_packed_tree_subject", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Final-GO subject")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FinalGoPackedTreeAuthorityRedTeamTests(unittest.TestCase):
    def _git(self, repo: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
        return subprocess.check_output([GIT, "-C", str(repo), *args], input=input_bytes)

    def _make_repository(self, repo: Path) -> tuple[str, str, str, bytes]:
        repo.mkdir(parents=True)
        subprocess.run([GIT, "init", "-q", str(repo)], check=True)
        subprocess.run([GIT, "-C", str(repo), "config", "user.email", "nembra@example.invalid"], check=True)
        subprocess.run([GIT, "-C", str(repo), "config", "user.name", "Nembra Final-GO Red Team"], check=True)

        product = repo / "Product.swift"
        accepted_payload = b"let authority = \"accepted\"\n"
        product.write_bytes(accepted_payload)
        subprocess.run([GIT, "-C", str(repo), "add", "Product.swift"], check=True)
        subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "accepted candidate"], check=True)
        accepted_source = self._git(repo, "rev-parse", "HEAD").decode("ascii").strip()

        attacker_payload = b"let authority = \"attacker\"\n"
        product.write_bytes(attacker_payload)
        subprocess.run([GIT, "-C", str(repo), "add", "Product.swift"], check=True)
        subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "attacker candidate"], check=True)
        attacker_commit = self._git(repo, "rev-parse", "HEAD").decode("ascii").strip()
        attacker_blob = self._git(repo, "rev-parse", "HEAD:Product.swift").decode("ascii").strip()
        self.assertEqual(git_blob_oid(attacker_payload), attacker_blob)

        # Final-GO intentionally allows these separately authenticated field
        # inputs outside the tracked product tree. They keep the fixture focused
        # on accepted-tree authority rather than unrelated preflight failures.
        for relative in ("LocalSecrets", "Pods", "NembraCapture.xcworkspace"):
            (repo / relative).mkdir()
        (repo / "Podfile.lock").write_text("fixture\n", encoding="utf-8")

        # Move the branch ref back to the accepted source without changing the
        # physical worktree. HEAD therefore names the exact accepted SHA while
        # Product.swift still contains the attacker's bytes.
        subprocess.run([GIT, "-C", str(repo), "update-ref", "HEAD", accepted_source], check=True)
        return accepted_source, attacker_commit, attacker_blob, attacker_payload

    def _forge_commit_pack_alias(self, repo: Path, *, attacker_commit: str, accepted_source: str) -> Path:
        pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
        pack_hash = subprocess.check_output(
            [GIT, "-C", str(repo), "pack-objects", str(pack_prefix)],
            input=(attacker_commit + "\n").encode("ascii"),
        ).decode("ascii").strip()

        # Force accepted-source lookup through the attacker's packed commit.
        for oid in (attacker_commit, accepted_source):
            loose = repo / ".git" / "objects" / oid[:2] / oid[2:]
            if loose.exists():
                loose.unlink()

        index = repo / ".git" / "objects" / "pack" / f"pack-{pack_hash}.idx"
        data = bytearray(index.read_bytes())
        self.assertEqual(data[:4], b"\xfftOc")
        self.assertEqual(struct.unpack(">I", data[4:8])[0], 2)

        fanout_offset = 8
        names_offset = fanout_offset + 256 * 4
        count = struct.unpack(">I", data[fanout_offset + 255 * 4 : fanout_offset + 256 * 4])[0]
        self.assertEqual(count, 1, "fixture pack must contain exactly one attacker commit")

        data[names_offset : names_offset + 20] = bytes.fromhex(accepted_source)
        first_byte = int(accepted_source[:2], 16)
        for index_value in range(256):
            struct.pack_into(">I", data, fanout_offset + index_value * 4, 0 if index_value < first_byte else 1)

        # Recompute the v2 index checksum after renaming the single packed object.
        data[-20:] = hashlib.sha1(data[:-20]).digest()
        index.write_bytes(data)
        return index

    def test_final_go_must_not_accept_physical_attacker_tree_from_forged_accepted_commit_lookup(self) -> None:
        final_go = load_final_go_module()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-packed-tree-") as directory:
            repo = Path(directory) / "repo"
            accepted_source, attacker_commit, attacker_blob, attacker_payload = self._make_repository(repo)
            forged_index = self._forge_commit_pack_alias(
                repo,
                attacker_commit=attacker_commit,
                accepted_source=accepted_source,
            )

            # The public identity string still resolves as the exact accepted
            # source, but ordinary ls-tree consumes the aliased attacker commit.
            resolved = self._git(repo, "rev-parse", "--verify", f"{accepted_source}^{{commit}}").decode("ascii").strip()
            self.assertEqual(resolved, accepted_source)
            tree = self._git(repo, "ls-tree", "-r", accepted_source).decode("utf-8")
            self.assertIn(f"blob {attacker_blob}\tProduct.swift", tree)
            self.assertEqual((repo / "Product.swift").read_bytes(), attacker_payload)

            # The forged pack is intentionally invalid under full Git integrity
            # verification; Final-GO must independently detect that integrity
            # failure rather than treating ordinary object lookup as authority.
            verify = subprocess.run(
                [GIT, "verify-pack", "-v", str(forged_index)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(verify.returncode, 0)

            with self.assertRaises(
                RuntimeError,
                msg="Final-GO admitted an attacker physical tree because its accepted commit/tree mapping came from unverified local Git object lookup",
            ):
                final_go._audit_candidate_tree(repo, accepted_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
