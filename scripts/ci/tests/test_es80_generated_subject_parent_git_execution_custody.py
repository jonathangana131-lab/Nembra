#!/usr/bin/env python3
"""Regression for R3 authenticated-stationary parent execution custody.

The generated-subject Final-GO child may execute its authenticated-stationary
parent only from the exact accepted Git object. Mutable checkout bytes are never
an execution subject, even when index flags hide their replacement.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
R3_RELATIVE = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
BASE_RELATIVE = "scripts/ci/es80_authenticated_stationary_final_go.py"
PARENT_SOURCE_SHA = "3fdd32551831c3469e0853ddcee8fa828d38b87b"
PARENT_MODULE_BLOB = "b0664c734004c2265b05d23ec58756806ff62f2c"


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["/usr/bin/git", "-C", str(root), *arguments],
        text=True,
    ).strip()


class GeneratedSubjectParentGitExecutionCustodyTests(unittest.TestCase):
    def test_hidden_base_worktree_replacement_never_executes_from_r3_loader(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-parent-git-exec-") as temporary:
            root = Path(temporary) / "repo"
            subprocess.run(
                ["/usr/bin/git", "clone", "--shared", "--quiet", str(REPOSITORY), str(root)],
                check=True,
            )
            source = git(REPOSITORY, "rev-parse", "HEAD")
            subprocess.run(["/usr/bin/git", "-C", str(root), "checkout", "-q", source], check=True)

            r3 = root / R3_RELATIVE
            base = root / BASE_RELATIVE
            self.assertEqual(
                git(root, "rev-parse", f"HEAD:{BASE_RELATIVE}"),
                PARENT_MODULE_BLOB,
                "the exact checked-out R3 tree must own the pinned authenticated-stationary parent blob",
            )

            sentinel = root / "attacker-base-executed"
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "update-index", "--assume-unchanged", BASE_RELATIVE],
                check=True,
            )
            base.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                "PROC = 'ATTACKER'\n",
                encoding="utf-8",
            )
            self.assertNotEqual(
                git(root, "hash-object", "--no-filters", "--", BASE_RELATIVE),
                PARENT_MODULE_BLOB,
            )
            self.assertEqual(git(root, "status", "--porcelain=v1", "--untracked-files=all"), "")

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("r3_parent_git_fixture", r3)
                if spec is None or spec.loader is None:
                    self.fail("could not load R3 fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                loaded = module._load_base_module()
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "R3 executed mutable authenticated-stationary parent worktree bytes",
            )
            self.assertEqual(
                getattr(loaded, "PROC", None),
                "ES80-AUTHENTICATED-STATIONARY-v1",
            )

    def test_source_binds_loaded_parent_to_live_parent_control_identity(self) -> None:
        source = (REPOSITORY / R3_RELATIVE).read_text(encoding="utf-8")
        self.assertIn(f'PARENT_SOURCE_SHA = "{PARENT_SOURCE_SHA}"', source)
        self.assertIn(f'PARENT_MODULE_BLOB = "{PARENT_MODULE_BLOB}"', source)
        self.assertIn("GIT_NO_REPLACE_OBJECTS", source)
        self.assertIn("parent_sha != PARENT_SOURCE_SHA", source)
        loader = source[source.index("def _load_base_module") : source.index("def _canonical_digest")]
        self.assertIn('f"HEAD:{PARENT_MODULE_PATH}"', loader)
        self.assertIn("cat-file", loader)
        self.assertIn("PARENT_MODULE_BLOB", loader)
        self.assertNotIn("spec_from_file_location", loader)
        self.assertNotIn("exec_module", loader)


if __name__ == "__main__":
    unittest.main(verbosity=2)
