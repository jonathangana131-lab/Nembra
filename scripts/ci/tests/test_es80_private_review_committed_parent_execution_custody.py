#!/usr/bin/env python3
"""Prove descendant pathname bytes cannot replace the exact current Final-GO parent.

The current Final-GO implementation is an exact-parent composition rather than a
copy of its predecessor. This regression therefore attacks the immediate parent
pin that the current source actually executes, while separately proving the real
repository commit/path/blob relationship. Historical compatibility identities
inside the accepted parent are deliberately not rewritten just to satisfy a test.
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
FIXTURE_CHILD_RELATIVE = "scripts/ci/private_review_child_fixture.py"
DIRECT_PARENT_RELATIVE = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"

CURRENT_DIRECT_PARENT_SOURCE = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
CURRENT_DIRECT_PARENT_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"


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

        # The reviewed constants are one provenance claim. Bind the real accepted
        # commit -> canonical module path -> exact Git blob before constructing the
        # replacement attack below.
        current_parent_blob = subprocess.check_output(
            [
                "/usr/bin/git",
                "-C",
                str(REPOSITORY),
                "rev-parse",
                f"{CURRENT_DIRECT_PARENT_SOURCE}:{DIRECT_PARENT_RELATIVE}",
            ],
            text=True,
        ).strip().lower()
        self.assertEqual(
            current_parent_blob,
            CURRENT_DIRECT_PARENT_BLOB,
            "current direct Final-GO parent source/path does not resolve to the pinned execution blob",
        )

        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-direct-parent-descendant-") as temporary:
            root = Path(temporary).resolve(strict=True)
            direct_parent = root / DIRECT_PARENT_RELATIVE
            fixture_child = root / FIXTURE_CHILD_RELATIVE
            sentinel = root / "committed-attacker-direct-parent-executed"
            direct_parent.parent.mkdir(parents=True, exist_ok=True)

            # Only the immediate interface consumed while the current child imports
            # is synthesized. _tree_entries deliberately resolves the externally
            # supplied accepted commit so the child's own provenance check remains
            # live in the fixture instead of being bypassed.
            direct_parent.write_text(
                "#!/usr/bin/env python3\n"
                "import subprocess\n"
                "import types\n"
                "from pathlib import Path\n"
                "class PrivateReviewGoError(RuntimeError): pass\n"
                "generated = types.SimpleNamespace(_load_base_module=lambda: None)\n"
                "class _DirectParent:\n"
                "    @staticmethod\n"
                "    def _tree_entries(root, source):\n"
                "        path='scripts/ci/es80_authenticated_stationary_private_review_final_go.py'\n"
                "        oid=subprocess.check_output([\n"
                "            '/usr/bin/git','-C',str(Path(root)),'rev-parse',f'{source}:{path}'\n"
                "        ], text=True).strip().lower()\n"
                "        return {path: (b'100644', oid)}\n"
                "_direct_parent = _DirectParent()\n",
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
            fixture_child.parent.mkdir(parents=True, exist_ok=True)
            fixture_child.write_text(patched_child, encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", FIXTURE_CHILD_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted direct-parent successor fixture"],
                check=True,
            )

            # Commit attacker-controlled descendant bytes at the canonical parent
            # pathname. The current child must still execute only accepted_blob.
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
            module_name = "private_review_committed_direct_parent_fixture"
            try:
                spec = importlib.util.spec_from_file_location(module_name, fixture_child)
                if spec is None or spec.loader is None:
                    self.fail("could not load Final-GO direct-parent fixture")
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
            finally:
                sys.modules.pop(module_name, None)
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "committed descendant parent bytes executed instead of exact accepted blob",
            )
            self.assertEqual(module.DIRECT_PARENT_SOURCE, accepted_source)
            self.assertEqual(module.DIRECT_PARENT_MODULE_GIT_BLOB, accepted_blob)
            self.assertEqual(module._parent.__nembra_exact_parent_source__, accepted_source)
            self.assertEqual(module._parent.__nembra_exact_parent_blob__, accepted_blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)
