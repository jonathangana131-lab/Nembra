#!/usr/bin/env python3
"""Runtime witness for trusted Capture Git-object byte custody.

A loose object file can be replaced under an existing SHA-1 pathname. Git's `cat-file` will decode
and return those replacement bytes without proving they still hash to the requested object name.
The trusted workflow therefore has to re-hash the exact materialized bytes before Bash sees them.
"""
from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest
import zlib


class TrustedXcodeGitObjectByteCustodyTests(unittest.TestCase):
    def test_cat_file_requested_oid_can_return_different_loose_object_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            subprocess.run(["/usr/bin/git", "init", "-q", str(repo)], check=True)

            expected = b"reviewed-producer\n"
            substituted = b"candidate-substitute\n"
            expected_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "hash-object", "-w", "--stdin"],
                input=expected,
            ).decode().strip()
            substituted_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", "/tmp", "hash-object", "--stdin"],
                input=substituted,
            ).decode().strip()
            self.assertNotEqual(expected_sha, substituted_sha)

            loose = repo / ".git" / "objects" / expected_sha[:2] / expected_sha[2:]
            raw_substitute = b"blob " + str(len(substituted)).encode("ascii") + b"\0" + substituted
            loose.write_bytes(zlib.compress(raw_substitute))

            returned = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "cat-file", "blob", expected_sha]
            )
            self.assertEqual(returned, substituted)

            materialized_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", "/tmp", "hash-object", "--stdin"],
                input=returned,
            ).decode().strip()
            self.assertEqual(materialized_sha, substituted_sha)
            self.assertNotEqual(materialized_sha, expected_sha)


if __name__ == "__main__":
    unittest.main()
