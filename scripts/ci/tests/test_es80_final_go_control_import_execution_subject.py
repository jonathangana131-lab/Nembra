#!/usr/bin/env python3
"""Expected-red regression for Final-GO control-module execution custody.

The control-plane may prove a worktree file equals its accepted Git blob at one
instant, but later authority code must not reopen that mutable pathname and
execute different bytes. This test swaps only the retained signed-artifact
module after the accepted-byte check and requires the later import to fail
closed rather than execute the replacement.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ISSUER = REPOSITORY / "scripts/ci/es80_authenticated_stationary_final_go.py"
SIGNED_ARTIFACT_RELATIVE = "scripts/ci/es80_authenticated_stationary_signed_artifact.py"
SIGNED_ARTIFACT = REPOSITORY / SIGNED_ARTIFACT_RELATIVE


def load_issuer():
    spec = importlib.util.spec_from_file_location("nembra_final_go", ISSUER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load authenticated-stationary Final-GO issuer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(*args: str) -> str:
    return subprocess.run(
        ["/usr/bin/git", "-C", str(REPOSITORY), *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={
            "PATH": "/usr/bin:/bin",
            "HOME": str(Path.home()),
            "GIT_NO_REPLACE_OBJECTS": "1",
        },
    ).stdout.strip()


class FinalGoControlImportExecutionSubjectTests(unittest.TestCase):
    def test_signed_artifact_import_cannot_execute_post_admission_replacement(self) -> None:
        issuer_source = ISSUER.read_text(encoding="utf-8")
        self.assertIn(
            'actual_blob=git(root,"hash-object","--no-filters","--",relative).lower()',
            issuer_source,
            "diagnostic must remain stacked on the control-worktree byte repair",
        )
        self.assertIn(
            'spec.loader.exec_module(module)',
            issuer_source,
            "diagnostic no longer exercises the mutable signed-artifact import boundary",
        )

        accepted_blob = git("rev-parse", f"HEAD:{SIGNED_ARTIFACT_RELATIVE}").lower()
        actual_blob = git("hash-object", "--no-filters", "--", SIGNED_ARTIFACT_RELATIVE).lower()
        self.assertEqual(actual_blob, accepted_blob)

        go = load_issuer()
        original = SIGNED_ARTIFACT.read_bytes()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-import-subject-") as temporary:
            marker = Path(temporary) / "replacement-executed"
            replacement = (
                "from pathlib import Path\n"
                "def retain_and_reinspect(*args, **kwargs):\n"
                f"    Path({str(marker)!r}).write_text('executed\\n', encoding='utf-8')\n"
                "    return {'authority': 'forged-retained-signed-artifact'}\n"
                "def reinspect_retained(*args, **kwargs):\n"
                f"    Path({str(marker)!r}).write_text('executed\\n', encoding='utf-8')\n"
                "    return {'authority': 'forged-retained-signed-artifact'}\n"
            ).encode("utf-8")
            try:
                # This swap occurs after the exact accepted-byte comparison that
                # #2739 adds to control_plane(), but before the later pathname import.
                SIGNED_ARTIFACT.write_bytes(replacement)
                self.assertNotEqual(
                    git("hash-object", "--no-filters", "--", SIGNED_ARTIFACT_RELATIVE).lower(),
                    accepted_blob,
                )

                # Required production behavior: authority must fail closed before
                # replacement Python bytes can execute. Current production is
                # expected RED because retained_signed_artifact() reopens pathname.
                with self.assertRaises(go.GoError):
                    go.retained_signed_artifact(
                        REPOSITORY,
                        "0" * 40,
                        Path(temporary) / "device.txt",
                        {},
                        Path(temporary) / "retained.ipa",
                    )
                self.assertFalse(marker.exists(), "replacement control-module bytes executed")
            finally:
                SIGNED_ARTIFACT.write_bytes(original)

        self.assertEqual(
            git("hash-object", "--no-filters", "--", SIGNED_ARTIFACT_RELATIVE).lower(),
            accepted_blob,
            "diagnostic failed to restore the accepted worktree subject",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
