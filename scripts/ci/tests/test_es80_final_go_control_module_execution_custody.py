#!/usr/bin/env python3
"""Production regression for Final-GO control-module execution custody.

Point-in-time worktree checks are not execution authority. Later signed-artifact
and publication helpers must execute the exact Git blob that the accepted
control-plane source commit names, even if the checkout pathname is replaced.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ISSUER = REPOSITORY / "scripts/ci/es80_authenticated_stationary_final_go.py"
SIGNED_RELATIVE = "scripts/ci/es80_authenticated_stationary_signed_artifact.py"
SIGNED = REPOSITORY / SIGNED_RELATIVE
PUBLICATION_RELATIVE = "scripts/ci/es80_today_final_go_publication.py"
PUBLICATION = REPOSITORY / PUBLICATION_RELATIVE


def load_issuer():
    spec = importlib.util.spec_from_file_location("nembra_final_go_execution_custody", ISSUER)
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
        env={"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"},
    ).stdout.strip()


class FinalGoControlModuleExecutionCustodyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.go = load_issuer()
        self.source = git("rev-parse", "HEAD").lower()

    def accepted_blob(self, relative: str) -> str:
        return git("rev-parse", f"{self.source}:{relative}").lower()

    def test_signed_artifact_helper_executes_accepted_blob_not_replaced_path(self) -> None:
        accepted_blob = self.accepted_blob(SIGNED_RELATIVE)
        original = SIGNED.read_bytes()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-signed-module-") as temporary:
            marker = Path(temporary) / "attacker-executed"
            replacement = (
                "from pathlib import Path\n"
                f"Path({str(marker)!r}).write_text('executed\\n', encoding='utf-8')\n"
                "def retain_and_reinspect(*args, **kwargs): return {'authority':'forged'}\n"
                "def reinspect_retained(*args, **kwargs): return {'authority':'forged'}\n"
            ).encode()
            try:
                SIGNED.write_bytes(replacement)
                module = self.go._load_accepted_control_module(
                    REPOSITORY,
                    self.source,
                    SIGNED_RELATIVE,
                    accepted_blob,
                    "nembra_test_signed_artifact",
                )
                self.assertFalse(marker.exists(), "replacement signed-artifact helper executed")
                self.assertTrue(callable(module.retain_and_reinspect))
                self.assertTrue(callable(module.reinspect_retained))
            finally:
                SIGNED.write_bytes(original)
        self.assertEqual(git("hash-object", "--no-filters", "--", SIGNED_RELATIVE).lower(), accepted_blob)

    def test_publication_helper_executes_accepted_blob_not_replaced_path(self) -> None:
        accepted_blob = self.accepted_blob(PUBLICATION_RELATIVE)
        original = PUBLICATION.read_bytes()
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-publication-module-") as temporary:
            marker = Path(temporary) / "attacker-executed"
            replacement = (
                "from pathlib import Path\n"
                f"Path({str(marker)!r}).write_text('executed\\n', encoding='utf-8')\n"
                "def publish_record_no_replace(*args, **kwargs): return 'forged'\n"
            ).encode()
            try:
                PUBLICATION.write_bytes(replacement)
                module = self.go._load_accepted_control_module(
                    REPOSITORY,
                    self.source,
                    PUBLICATION_RELATIVE,
                    accepted_blob,
                    "nembra_test_publication",
                )
                self.assertFalse(marker.exists(), "replacement publication helper executed")
                self.assertTrue(callable(module.publish_record_no_replace))
            finally:
                PUBLICATION.write_bytes(original)
        self.assertEqual(git("hash-object", "--no-filters", "--", PUBLICATION_RELATIVE).lower(), accepted_blob)

    def test_loader_rejects_blob_not_owned_by_exact_source_path(self) -> None:
        wrong_blob = self.accepted_blob(PUBLICATION_RELATIVE)
        with self.assertRaisesRegex(self.go.GoError, "accepted control-module blob"):
            self.go._load_accepted_control_module(
                REPOSITORY,
                self.source,
                SIGNED_RELATIVE,
                wrong_blob,
                "nembra_test_wrong_blob",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
