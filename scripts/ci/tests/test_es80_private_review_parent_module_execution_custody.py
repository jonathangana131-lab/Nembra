#!/usr/bin/env python3
"""Expected-red custody regression for the private-review Final-GO parent module.

The private-review child records and later verifies exact generated-parent Git blobs, but its
module-level `_load_generated_module()` currently executes the sibling checkout pathname before
those control-plane checks can run. A suppressed same-UID worktree replacement must never execute
merely by importing the child authority module.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
CHILD_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_RELATIVE = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
CHILD_RELATIVE = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"


class PrivateReviewParentModuleExecutionCustodyTests(unittest.TestCase):
    def test_hidden_parent_worktree_replacement_never_executes_before_authority_checks(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-parent-exec-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "attacker-parent-executed"
            child = root / CHILD_RELATIVE
            parent = root / PARENT_RELATIVE
            child.parent.mkdir(parents=True, exist_ok=True)
            child.write_bytes(CHILD_SOURCE.read_bytes())

            accepted_parent = (
                "#!/usr/bin/env python3\n"
                "def _current_generated_subject(_root):\n"
                "    return 'a' * 64\n"
            )
            parent.write_text(accepted_parent, encoding="utf-8")

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
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted private control fixture"],
                check=True,
            )

            accepted_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", f"HEAD:{PARENT_RELATIVE}"],
                text=True,
            ).strip()
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "update-index", "--assume-unchanged", PARENT_RELATIVE],
                check=True,
            )
            parent.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                "def _current_generated_subject(_root):\n"
                "    return 'a' * 64\n",
                encoding="utf-8",
            )

            current_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "hash-object", "--no-filters", "--", PARENT_RELATIVE],
                text=True,
            ).strip()
            self.assertNotEqual(current_blob, accepted_blob, "fixture did not replace accepted parent bytes")
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
                "fixture must model a replacement hidden from ordinary cleanliness checks",
            )

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("private_review_import_subject", child)
                if spec is None or spec.loader is None:
                    self.fail("could not load private-review control fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "private-review child executed mutable generated-parent worktree bytes before exact Git/control authority could be established",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
