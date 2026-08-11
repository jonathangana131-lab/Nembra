#!/usr/bin/env python3
"""Prove committed descendant predecessor bytes cannot replace exact accepted Final-GO code."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
CHILD_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
FIXTURE_CHILD_RELATIVE = "scripts/ci/private_review_child_fixture.py"
PREDECESSOR_RELATIVE = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"


class PrivateReviewCommittedParentExecutionCustodyTests(unittest.TestCase):
    def test_committed_descendant_predecessor_replacement_never_executes(self) -> None:
        child_source = CHILD_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            'PREVIOUS_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"',
            child_source,
        )
        self.assertIn(
            'PREVIOUS_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"',
            child_source,
        )
        self.assertIn("entries = _tree_entries(root, PREVIOUS_SOURCE)", child_source)
        self.assertIn("entry != (b\"100644\", PREVIOUS_MODULE_GIT_BLOB)", child_source)
        self.assertIn(
            "_verified_object_bytes(root, \"blob\", PREVIOUS_MODULE_GIT_BLOB",
            child_source,
        )

        with tempfile.TemporaryDirectory(prefix="nembra-private-predecessor-descendant-") as temporary:
            root = Path(temporary).resolve(strict=True)
            predecessor = root / PREDECESSOR_RELATIVE
            fixture_child = root / FIXTURE_CHILD_RELATIVE
            sentinel = root / "committed-attacker-predecessor-executed"
            predecessor.parent.mkdir(parents=True, exist_ok=True)

            predecessor.write_text(
                "#!/usr/bin/env python3\n"
                "import contextlib\n"
                "import types\n"
                "class PrivateReviewGoError(RuntimeError): pass\n"
                "_parent = types.SimpleNamespace(\n"
                "    __nembra_accepted_control_source__='fixture-historical-source',\n"
                "    __nembra_accepted_control_blob__='fixture-historical-blob',\n"
                ")\n"
                "PARENT_SOURCE='fixture-historical-source'\n"
                "PARENT_MODULE_PATH='fixture-historical.py'\n"
                "PARENT_MODULE_GIT_BLOB='fixture-historical-blob'\n"
                "generated=types.SimpleNamespace()\n"
                "def review_v5(*args, **kwargs): return {}\n"
                "def candidate_private_authority(*args, **kwargs): return {}\n"
                "def _physical_blob_oid(*args, **kwargs): return '0'*40\n"
                "def _audit_candidate_tree(*args, **kwargs): return {}\n"
                "@contextlib.contextmanager\n"
                "def _candidate_git_custody(*args, **kwargs):\n"
                "    yield\n"
                "def build(*args, **kwargs): return {}\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"],
                check=True,
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", PREDECESSOR_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted immediate predecessor"],
                check=True,
            )
            accepted_source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
            ).strip().lower()
            accepted_blob = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", f"{accepted_source}:{PREDECESSOR_RELATIVE}"],
                text=True,
            ).strip().lower()

            patched_child = child_source.replace(
                'PREVIOUS_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"',
                f'PREVIOUS_SOURCE = "{accepted_source}"',
                1,
            ).replace(
                'PREVIOUS_MODULE_GIT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"',
                f'PREVIOUS_MODULE_GIT_BLOB = "{accepted_blob}"',
                1,
            )
            self.assertIn(f'PREVIOUS_SOURCE = "{accepted_source}"', patched_child)
            self.assertIn(f'PREVIOUS_MODULE_GIT_BLOB = "{accepted_blob}"', patched_child)
            fixture_child.parent.mkdir(parents=True, exist_ok=True)
            fixture_child.write_text(patched_child, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", FIXTURE_CHILD_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted successor fixture"],
                check=True,
            )

            predecessor.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", PREDECESSOR_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "attacker replaces predecessor"],
                check=True,
            )

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location(
                    "private_review_committed_predecessor_fixture", fixture_child
                )
                if spec is None or spec.loader is None:
                    self.fail("could not load private-review fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "committed descendant predecessor bytes executed instead of exact accepted predecessor",
            )
            self.assertEqual(module._previous.__nembra_accepted_control_source__, accepted_source)
            self.assertEqual(module._previous.__nembra_accepted_control_blob__, accepted_blob)
            self.assertEqual(module._parent.__nembra_accepted_control_source__, "fixture-historical-source")
            self.assertEqual(module._parent.__nembra_accepted_control_blob__, "fixture-historical-blob")


if __name__ == "__main__":
    unittest.main(verbosity=2)
