#!/usr/bin/env python3
"""Regress trusted Capture Xcode process-startup and producer-object custody.

Two independent attack witnesses stay executable:
- ordinary noninteractive Bash consumes inherited BASH_ENV before its body, while privileged Bash
  does not; and
- `git cat-file blob <expected-oid>` can return substituted loose-object contents under the expected
  object name, so the exact returned bytes must be independently re-hashed before interpretation.

The workflow source must then bind both facts into the authority-producing path.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
PRODUCER_BLOB = "4e9ae0cb6728dc68d9b8dd43aac7c50128702ed9"
PRIVILEGED_SHELL = "shell: /bin/bash -p -e -o pipefail {0}"


def _step(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^      - name: {re.escape(name)}\n(?P<body>.*?)(?=^      - name: |\Z)",
        source,
    )
    if match is None:
        raise AssertionError(f"missing trusted workflow step: {name}")
    return match.group(0)


class TrustedXcodeProcessObjectCustodyTests(unittest.TestCase):
    def test_privileged_bash_suppresses_inherited_bash_env(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            hook = root / "hook.sh"
            marker = root / "marker"
            hook.write_text('printf "hook\\n" >> "$HOOK_MARKER"\n', encoding="utf-8")
            environment = os.environ.copy()
            environment["BASH_ENV"] = str(hook)
            environment["HOOK_MARKER"] = str(marker)

            ordinary = subprocess.run(
                ["/bin/bash", "-c", 'printf "body\\n" >> "$HOOK_MARKER"'],
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(ordinary.returncode, 0, ordinary.stderr.decode(errors="replace"))
            self.assertEqual(marker.read_text(encoding="utf-8"), "hook\nbody\n")

            marker.unlink()
            privileged = subprocess.run(
                ["/bin/bash", "-p", "-c", 'printf "body\\n" >> "$HOOK_MARKER"'],
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(privileged.returncode, 0, privileged.stderr.decode(errors="replace"))
            self.assertEqual(marker.read_text(encoding="utf-8"), "body\n")

    def test_cat_file_object_name_does_not_authenticate_loose_object_contents(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            subprocess.run(["/usr/bin/git", "init", "-q", str(repo)], check=True)

            good = b"trusted-producer\n"
            evil = b"candidate-substitute\n"
            good_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "hash-object", "-w", "--stdin"],
                input=good,
            ).decode().strip()
            evil_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "hash-object", "--stdin"],
                input=evil,
            ).decode().strip()
            self.assertNotEqual(good_sha, evil_sha)

            loose = repo / ".git" / "objects" / good_sha[:2] / good_sha[2:]
            raw_evil = b"blob " + str(len(evil)).encode("ascii") + b"\0" + evil
            loose.write_bytes(zlib.compress(raw_evil))

            returned = subprocess.check_output(
                ["/usr/bin/git", "-C", str(repo), "cat-file", "blob", good_sha]
            )
            self.assertEqual(returned, evil)
            materialized_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", "/tmp", "hash-object", "--stdin"],
                input=returned,
            ).decode().strip()
            self.assertEqual(materialized_sha, evil_sha)
            self.assertNotEqual(materialized_sha, good_sha)

    def test_authority_step_closes_startup_and_exact_byte_boundaries(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        step = _step(source, "Build, test, and capture Simulator states")

        self.assertIn(PRIVILEGED_SHELL, step)
        self.assertIn(f'expected_blob="{PRODUCER_BLOB}"', step)
        self.assertIn('/usr/bin/git cat-file blob "$expected_blob"', step)
        self.assertIn('/usr/bin/git -C /tmp hash-object --stdin', step)
        self.assertIn('test "$materialized_blob" = "$expected_blob"', step)
        self.assertIn("/bin/bash -p -c 'source /dev/stdin'", step)
        self.assertIn('/usr/bin/env -i', step)
        self.assertNotRegex(step, r"(?m)^\s+env -i\b")
        self.assertNotRegex(
            step,
            r"/usr/bin/git cat-file blob \"\$expected_blob\"\s*\\?\n\s*\|",
            "cat-file output must be re-hashed before it can reach Bash",
        )

        materialize = step.index('/usr/bin/git cat-file blob "$expected_blob"')
        rehash = step.index('/usr/bin/git -C /tmp hash-object --stdin')
        compare = step.index('test "$materialized_blob" = "$expected_blob"')
        execute = step.index("/bin/bash -p -c 'source /dev/stdin'")
        self.assertLess(materialize, rehash)
        self.assertLess(rehash, compare)
        self.assertLess(compare, execute)

    def test_retained_evidence_verifier_also_ignores_persisted_bash_startup(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        step = _step(source, "Verify retained Capture evidence against trusted resolver authority")
        self.assertIn(PRIVILEGED_SHELL, step)
        self.assertIn("/usr/bin/python3 -I -", step)


if __name__ == "__main__":
    unittest.main()
