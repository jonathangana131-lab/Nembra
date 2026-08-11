#!/usr/bin/env python3
"""Expected-red regression: R3 must not execute a child-committed replacement of its exact parent module."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
R3_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
R3_RELATIVE = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
BASE_RELATIVE = "scripts/ci/es80_authenticated_stationary_final_go.py"


class GeneratedSubjectCommittedParentExecutionCustodyTests(unittest.TestCase):
    def test_child_committed_parent_replacement_never_executes_before_exact_parent_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-committed-parent-exec-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "child-committed-parent-executed"
            r3 = root / R3_RELATIVE
            base = root / BASE_RELATIVE
            r3.parent.mkdir(parents=True, exist_ok=True)
            r3.write_bytes(R3_SOURCE.read_bytes())
            base.write_text("#!/usr/bin/env python3\nBASE_MARKER = 'accepted-parent'\n", encoding="utf-8")

            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"],
                check=True,
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted exact parent fixture"],
                check=True,
            )
            parent_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
            ).strip()
            parent_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", f"{parent_sha}:{BASE_RELATIVE}"],
                text=True,
            ).strip()

            base.write_text(
                "#!/usr/bin/env python3\nfrom pathlib import Path\n"
                + f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                + "BASE_MARKER = 'child-substituted'\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", BASE_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "child replaces inherited parent module"],
                check=True,
            )
            child_sha = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
            ).strip()
            child_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", f"{child_sha}:{BASE_RELATIVE}"],
                text=True,
            ).strip()

            self.assertNotEqual(child_sha, parent_sha)
            self.assertNotEqual(child_blob, parent_blob)
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
                "fixture must be a fully committed clean child, not a worktree substitution",
            )

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("r3_committed_parent_fixture", r3)
                if spec is None or spec.loader is None:
                    self.fail("could not load R3 fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                loaded = module._load_base_module()
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "R3 executed a child-committed replacement of the inherited authenticated-stationary parent before exact parent authority was established",
            )
            self.assertEqual(
                getattr(loaded, "BASE_MARKER", None),
                "accepted-parent",
                "R3 parent execution must be tied to the exact accepted parent subject, not child HEAD",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
