#!/usr/bin/env python3
"""Reject a committed descendant replacement of the private-review generated parent."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
CHILD_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
CHILD_RELATIVE = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_RELATIVE = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
PIN_PREFIX = 'PARENT_GENERATED_MODULE_GIT_BLOB = "'


class PrivateReviewCommittedParentExecutionCustodyTests(unittest.TestCase):
    def test_committed_descendant_parent_replacement_fails_before_parent_code_executes(self) -> None:
        child_source = CHILD_SOURCE.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory(prefix="nembra-private-parent-descendant-") as temporary:
            root = Path(temporary).resolve(strict=True)
            child = root / CHILD_RELATIVE
            parent = root / PARENT_RELATIVE
            sentinel = root / "committed-attacker-parent-executed"
            parent.parent.mkdir(parents=True, exist_ok=True)
            parent.write_text(
                "#!/usr/bin/env python3\n"
                "def _current_generated_subject(_root, _source, _base):\n"
                "    return 'a' * 64\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", PARENT_RELATIVE], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted generated parent"], check=True)
            accepted_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", f"HEAD:{PARENT_RELATIVE}"], text=True
            ).strip()

            start = child_source.index(PIN_PREFIX) + len(PIN_PREFIX)
            end = child_source.index('"', start)
            patched_child = child_source[:start] + accepted_blob + child_source[end:]
            child.parent.mkdir(parents=True, exist_ok=True)
            child.write_text(patched_child, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", CHILD_RELATIVE], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted private child"], check=True)

            parent.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                "def _current_generated_subject(_root, _source, _base):\n"
                "    return 'b' * 64\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", PARENT_RELATIVE], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "attacker replaces generated parent"], check=True)

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("private_review_committed_parent_fixture", child)
                if spec is None or spec.loader is None:
                    self.fail("could not load private-review fixture")
                module = importlib.util.module_from_spec(spec)
                with self.assertRaises(Exception):
                    spec.loader.exec_module(module)
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "committed replacement parent code executed before exact accepted parent-blob rejection",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
