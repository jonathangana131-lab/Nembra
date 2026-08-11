#!/usr/bin/env python3
"""Prove committed descendant direct-parent bytes cannot replace exact accepted Final-GO code."""
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
DIRECT_PARENT_RELATIVE = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"

CURRENT_DIRECT_PARENT_SOURCE = "471cc025b332f4df8b43a98d709710aeb4e0698f"
CURRENT_DIRECT_PARENT_BLOB = "48ce4bd8f933ae062eaaadd0d017d13c781a8c02"


class PrivateReviewCommittedParentExecutionCustodyTests(unittest.TestCase):
    def test_committed_descendant_direct_parent_replacement_never_executes(self) -> None:
        child_source = CHILD_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            f'DIRECT_PARENT_SOURCE = "{CURRENT_DIRECT_PARENT_SOURCE}"',
            child_source,
            "fixture must track the current immediate Final-GO parent pin",
        )
        self.assertIn(
            f'DIRECT_PARENT_MODULE_GIT_BLOB = "{CURRENT_DIRECT_PARENT_BLOB}"',
            child_source,
            "fixture must track the current immediate Final-GO parent blob pin",
        )

        with tempfile.TemporaryDirectory(prefix="nembra-private-direct-parent-descendant-") as temporary:
            root = Path(temporary).resolve(strict=True)
            direct_parent = root / DIRECT_PARENT_RELATIVE
            fixture_child = root / FIXTURE_CHILD_RELATIVE
            sentinel = root / "committed-attacker-direct-parent-executed"
            direct_parent.parent.mkdir(parents=True, exist_ok=True)

            # The synthetic accepted immediate parent exposes exactly the public
            # compatibility and helper surface the current successor consumes at
            # import time. Its inherited historical parent remains a separate
            # identity, matching production's #2921 -> #2873 topology.
            direct_parent.write_text(
                "#!/usr/bin/env python3\n"
                "import contextlib\n"
                "import types\n"
                "class PrivateReviewGoError(RuntimeError): pass\n"
                "_parent = types.SimpleNamespace(\n"
                "    __nembra_accepted_control_source__='fixture-historical-source',\n"
                "    __nembra_accepted_control_blob__='fixture-historical-blob',\n"
                "    build=lambda **kwargs: {},\n"
                ")\n"
                "generated = types.SimpleNamespace(_load_base_module=lambda: None)\n"
                "PARENT_SOURCE='fixture-historical-source'\n"
                "PARENT_MODULE_GIT_BLOB='fixture-historical-blob'\n"
                "FIELD_INPUT_DIRECTORIES=()\n"
                "FIELD_INPUT_FILES=()\n"
                "def review_v5(*args, **kwargs): return {}\n"
                "def candidate_private_authority(*args, **kwargs): return {}\n"
                "def _physical_blob_oid(*args, **kwargs): return '0'*40\n"
                "def _audit_candidate_tree(*args, **kwargs): return {}\n"
                "@contextlib.contextmanager\n"
                "def _candidate_git_custody(*args, **kwargs):\n"
                "    yield\n"
                "def _tree_entries(*args, **kwargs): return {}\n"
                "@contextlib.contextmanager\n"
                "def _current_vnode_authority(*args, **kwargs):\n"
                "    yield\n",
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
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", DIRECT_PARENT_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted immediate Final-GO parent"],
                check=True,
            )
            accepted_source = subprocess.check_output(
                ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
            ).strip().lower()
            accepted_blob = subprocess.check_output(
                [
                    "/usr/bin/git",
                    "-C",
                    str(root),
                    "rev-parse",
                    f"{accepted_source}:{DIRECT_PARENT_RELATIVE}",
                ],
                text=True,
            ).strip().lower()

            patched_child = child_source.replace(
                f'DIRECT_PARENT_SOURCE = "{CURRENT_DIRECT_PARENT_SOURCE}"',
                f'DIRECT_PARENT_SOURCE = "{accepted_source}"',
                1,
            ).replace(
                f'DIRECT_PARENT_MODULE_GIT_BLOB = "{CURRENT_DIRECT_PARENT_BLOB}"',
                f'DIRECT_PARENT_MODULE_GIT_BLOB = "{accepted_blob}"',
                1,
            )
            self.assertIn(f'DIRECT_PARENT_SOURCE = "{accepted_source}"', patched_child)
            self.assertIn(f'DIRECT_PARENT_MODULE_GIT_BLOB = "{accepted_blob}"', patched_child)
            # The historical compatibility pins are intentionally untouched.
            self.assertIn('PARENT_SOURCE = _direct_parent.PARENT_SOURCE', patched_child)
            self.assertIn('PARENT_MODULE_GIT_BLOB = _direct_parent.PARENT_MODULE_GIT_BLOB', patched_child)

            fixture_child.parent.mkdir(parents=True, exist_ok=True)
            fixture_child.write_text(patched_child, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", FIXTURE_CHILD_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted direct-parent successor fixture"],
                check=True,
            )

            # Commit attacker-controlled descendant bytes at the canonical direct
            # parent pathname. The successor must still execute only the accepted
            # blob pinned above, never these newer pathname bytes.
            direct_parent.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", DIRECT_PARENT_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "attacker replaces immediate Final-GO parent"],
                check=True,
            )

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location(
                    "private_review_committed_direct_parent_fixture", fixture_child
                )
                if spec is None or spec.loader is None:
                    self.fail("could not load private-review direct-parent fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "committed descendant direct-parent bytes executed instead of exact accepted blob",
            )
            self.assertEqual(module.DIRECT_PARENT_SOURCE, accepted_source)
            self.assertEqual(module.DIRECT_PARENT_MODULE_GIT_BLOB, accepted_blob)
            self.assertEqual(module._direct_parent.__nembra_direct_parent_source__, accepted_source)
            self.assertEqual(module._direct_parent.__nembra_direct_parent_blob__, accepted_blob)
            self.assertEqual(module._parent.__nembra_accepted_control_source__, "fixture-historical-source")
            self.assertEqual(module._parent.__nembra_accepted_control_blob__, "fixture-historical-blob")
            self.assertEqual(module.PARENT_SOURCE, "fixture-historical-source")
            self.assertEqual(module.PARENT_MODULE_GIT_BLOB, "fixture-historical-blob")


if __name__ == "__main__":
    unittest.main(verbosity=2)
