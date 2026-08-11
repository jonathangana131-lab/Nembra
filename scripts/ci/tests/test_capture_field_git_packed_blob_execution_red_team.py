#!/usr/bin/env python3
"""Expected-red witness for Git packed-blob execution authority in the field installer.

The accepted commit/tree and physical worktree can remain exact while a mutable
pack index aliases an accepted blob OID to different packed bytes. Git object
lookup may return those bytes unless the consumer independently re-hashes the
payload against the OID supplied by the already-verified accepted tree.
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


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


class CaptureFieldPackedBlobExecutionRedTeamTests(unittest.TestCase):
    def _git(self, repo: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
        return subprocess.check_output(
            [GIT, "-C", str(repo), *args],
            input=input_bytes,
        )

    def _make_accepted_repository(self, repo: Path) -> tuple[str, str, bytes]:
        repo.mkdir(parents=True)
        subprocess.run([GIT, "init", "-q", str(repo)], check=True)
        subprocess.run([GIT, "-C", str(repo), "config", "user.email", "nembra@example.invalid"], check=True)
        subprocess.run([GIT, "-C", str(repo), "config", "user.name", "Nembra Red Team"], check=True)
        bootstrap = repo / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
        bootstrap.parent.mkdir(parents=True)
        accepted_payload = b"#!/bin/bash\necho accepted-bootstrap\n"
        bootstrap.write_bytes(accepted_payload)
        subprocess.run([GIT, "-C", str(repo), "add", "Scripts/bootstrap_capture_tuya_sdk.sh"], check=True)
        subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "accepted fixture"], check=True)
        source = self._git(repo, "rev-parse", "HEAD").decode("ascii").strip()
        accepted_blob = self._git(
            repo, "rev-parse", "HEAD:Scripts/bootstrap_capture_tuya_sdk.sh"
        ).decode("ascii").strip()
        self.assertEqual(git_blob_oid(accepted_payload), accepted_blob)
        return source, accepted_blob, accepted_payload

    def _forge_single_object_pack_alias(
        self,
        repo: Path,
        *,
        attacker_payload: bytes,
        accepted_blob_oid: str,
    ) -> Path:
        attacker_oid = self._git(repo, "hash-object", "-w", "--stdin", input_bytes=attacker_payload).decode("ascii").strip()
        pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
        pack_hash = subprocess.check_output(
            [GIT, "-C", str(repo), "pack-objects", str(pack_prefix)],
            input=(attacker_oid + "\n").encode("ascii"),
        ).decode("ascii").strip()

        # Force accepted-blob lookup through the packed object whose index name
        # we are about to alias. The accepted commit/tree objects remain genuine.
        for oid in (attacker_oid, accepted_blob_oid):
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
        self.assertEqual(count, 1, "fixture pack must contain exactly one attacker object")

        data[names_offset : names_offset + 20] = bytes.fromhex(accepted_blob_oid)
        first_byte = int(accepted_blob_oid[:2], 16)
        for index_value in range(256):
            struct.pack_into(">I", data, fanout_offset + index_value * 4, 0 if index_value < first_byte else 1)

        # A v2 SHA-1 pack index ends with the pack checksum followed by the index
        # checksum. Recompute only the latter after rewriting the object-name table.
        data[-20:] = hashlib.sha1(data[:-20]).digest()
        index.write_bytes(data)
        return index

    def test_pack_index_alias_can_change_git_show_bytes_while_tree_and_physical_file_stay_accepted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-packed-blob-redteam-") as directory:
            repo = Path(directory) / "repo"
            source, accepted_blob, accepted_payload = self._make_accepted_repository(repo)
            attacker_payload = b"#!/bin/bash\necho attacker-executed\n"
            forged_index = self._forge_single_object_pack_alias(
                repo,
                attacker_payload=attacker_payload,
                accepted_blob_oid=accepted_blob,
            )

            # Commit/tree identity and the raw physical worktree remain accepted.
            resolved = self._git(repo, "rev-parse", "--verify", f"{source}^{{commit}}").decode("ascii").strip()
            self.assertEqual(resolved, source)
            tree = self._git(repo, "ls-tree", "-r", source).decode("utf-8")
            self.assertIn(f"blob {accepted_blob}\tScripts/bootstrap_capture_tuya_sdk.sh", tree)
            physical = (repo / "Scripts" / "bootstrap_capture_tuya_sdk.sh").read_bytes()
            self.assertEqual(physical, accepted_payload)
            self.assertEqual(git_blob_oid(physical), accepted_blob)

            # But ordinary object lookup trusts the forged pack-index name and
            # returns attacker bytes for the accepted blob identity.
            shown = self._git(repo, "show", f"{source}:Scripts/bootstrap_capture_tuya_sdk.sh")
            cat = self._git(repo, "cat-file", "blob", accepted_blob)
            self.assertEqual(shown, attacker_payload)
            self.assertEqual(cat, attacker_payload)
            self.assertNotEqual(git_blob_oid(shown), accepted_blob)

            verify = subprocess.run(
                [GIT, "verify-pack", "-v", str(forged_index)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(verify.returncode, 0, "fixture must be detectably invalid under verify-pack")

    def test_installer_must_not_stream_unverified_git_object_payloads_directly_into_interpreters(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")

        bootstrap_direct = re.compile(
            r'run_authority_git show "\$SOURCE_SHA:\$relative_path"\s*\|\s*\n\s*/bin/bash'
        )
        private_runner_direct = re.compile(
            r'run_authority_git show "\$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner\.py"\s*\|\s*\n\s*/usr/bin/env -i'
        )

        self.assertIsNone(
            bootstrap_direct.search(source),
            "accepted bootstrap Git bytes are streamed directly into Bash without independently re-hashing the returned payload against its accepted blob OID",
        )
        self.assertIsNone(
            private_runner_direct.search(source),
            "accepted private-runner Git bytes are streamed directly into Python without independently re-hashing the returned payload against its accepted blob OID",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
