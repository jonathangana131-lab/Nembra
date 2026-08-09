#!/usr/bin/env python3
"""Expected-red contract for trusted Simulator producer Git-object byte custody.

The trusted default-branch workflow pins the producer OID and later streams `git cat-file blob OID`
into Bash. Candidate-controlled host code currently executes between checkout/pinning and that stream.
A same-UID process can write a loose object at the pinned OID pathname whose decompressed bytes do
not actually hash to that OID. `git cat-file` returns those substituted bytes successfully; it does
not re-hash them on read.

Therefore either no candidate-controlled host process may run before the authority-producing stream,
or the exact `cat-file` bytes must be independently re-hashed against the pinned OID before those
same bytes reach the interpreter.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
BUILD_STEP = "Build, test, and capture Simulator states"
CANDIDATE_HOST_STEPS = (
    "Validate project structure",
    "Validate core package",
    "Validate Capture package",
    "Validate signed field evidence tooling",
    "Validate signed field candidate producer source",
    "Validate offline field authorization signer",
)


def run_git(root: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    completed = subprocess.run(
        ["/usr/bin/git", "-C", str(root), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env={
            "PATH": "/usr/bin:/bin",
            "HOME": str(root),
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_NO_REPLACE_OBJECTS": "1",
        },
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr.decode("utf-8", errors="replace"))
    return completed.stdout


def git_blob_oid(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def step_body(workflow: str, name: str) -> str:
    marker = f"      - name: {name}\n"
    start = workflow.index(marker)
    next_step = workflow.find("\n      - name: ", start + len(marker))
    return workflow[start:] if next_step < 0 else workflow[start:next_step]


class TrustedProducerGitObjectCustodyExpectedRedTests(unittest.TestCase):
    def test_cat_file_accepts_substituted_loose_bytes_under_pinned_oid_path(self) -> None:
        """Mechanical witness: cat-file names an object; it does not authenticate bytes on read."""
        with tempfile.TemporaryDirectory(prefix="nembra-object-custody-") as temporary:
            repo = Path(temporary)
            run_git(repo, "init", "-q")

            trusted = b"#!/bin/bash\nprintf 'trusted\\n'\n"
            expected_oid = run_git(repo, "hash-object", "-w", "--stdin", input_bytes=trusted).decode().strip()
            self.assertEqual(expected_oid, git_blob_oid(trusted))

            substituted = b"#!/bin/bash\nprintf 'candidate-substituted\\n'\n"
            self.assertNotEqual(git_blob_oid(substituted), expected_oid)

            object_path = repo / ".git" / "objects" / expected_oid[:2] / expected_oid[2:]
            object_path.parent.mkdir(parents=True, exist_ok=True)
            forged_raw = b"blob " + str(len(substituted)).encode("ascii") + b"\0" + substituted
            object_path.write_bytes(zlib.compress(forged_raw))

            materialized = run_git(repo, "cat-file", "blob", expected_oid)
            self.assertEqual(materialized, substituted)
            self.assertNotEqual(git_blob_oid(materialized), expected_oid)

    def test_current_worktree_reproof_does_not_authenticate_cat_file_stream(self) -> None:
        """Mirror the production pattern: trusted worktree hash can pass while cat-file bytes differ."""
        with tempfile.TemporaryDirectory(prefix="nembra-worktree-vs-object-") as temporary:
            repo = Path(temporary)
            run_git(repo, "init", "-q")
            producer = repo / "producer.sh"
            trusted = b"#!/bin/bash\nprintf 'trusted\\n'\n"
            producer.write_bytes(trusted)
            expected_oid = run_git(repo, "hash-object", "-w", "producer.sh").decode().strip()

            substituted = b"#!/bin/bash\nprintf 'substituted-object\\n'\n"
            object_path = repo / ".git" / "objects" / expected_oid[:2] / expected_oid[2:]
            forged_raw = b"blob " + str(len(substituted)).encode("ascii") + b"\0" + substituted
            object_path.write_bytes(zlib.compress(forged_raw))

            worktree_oid = run_git(repo, "hash-object", "--", "producer.sh").decode().strip()
            self.assertEqual(worktree_oid, expected_oid, "trusted worktree re-proof should still pass")
            self.assertEqual(run_git(repo, "cat-file", "blob", expected_oid), substituted)

    def test_trusted_workflow_closes_object_store_check_use_gap(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        build_index = workflow.index(f"      - name: {BUILD_STEP}\n")
        candidate_indices = [
            workflow.index(f"      - name: {name}\n")
            for name in CANDIDATE_HOST_STEPS
            if f"      - name: {name}\n" in workflow
        ]
        candidate_before_authority = any(index < build_index for index in candidate_indices)
        if not candidate_before_authority:
            return

        body = step_body(workflow, BUILD_STEP)
        cat_marker = '/usr/bin/git cat-file blob "$expected_blob"'
        cat_index = body.find(cat_marker)
        self.assertGreaterEqual(cat_index, 0, "trusted workflow no longer materializes the pinned producer object")

        bash_matches = list(re.finditer(r"/bin/bash\b", body[cat_index:]))
        self.assertTrue(bash_matches, "trusted workflow no longer interprets pinned producer bytes with Bash")
        bash_index = cat_index + bash_matches[-1].start()
        custody_segment = body[cat_index:bash_index]

        # Accept any implementation that independently hashes the exact materialized stream before
        # interpretation. A worktree hash before `cat-file` is intentionally insufficient.
        independent_stream_hash = (
            "hash-object --stdin" in custody_segment
            or "hashlib.sha1" in custody_segment
            or "trusted producer object bytes failed Git-blob verification" in custody_segment
        )
        self.assertTrue(
            independent_stream_hash,
            "candidate-controlled host code runs before authority and the exact git cat-file producer "
            "bytes are not independently re-hashed against the pinned OID before Bash interprets them",
        )


if __name__ == "__main__":
    unittest.main()
