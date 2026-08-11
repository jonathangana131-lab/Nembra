#!/usr/bin/env python3
"""Regression for private-review R4 generated-parent module execution custody."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
CHILD_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PARENT_RELATIVE = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
CHILD_RELATIVE = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
PIN_RE = re.compile(r'GENERATED_PARENT_MODULE_GIT_BLOB = "[0-9a-f]{40,64}"')


class PrivateReviewParentModuleExecutionCustodyTests(unittest.TestCase):
    def _fixture(self, root: Path) -> tuple[Path, Path, str]:
        child = root / CHILD_RELATIVE
        parent = root / PARENT_RELATIVE
        child.parent.mkdir(parents=True, exist_ok=True)
        accepted_parent = (
            "#!/usr/bin/env python3\n"
            "def _current_generated_subject(_root):\n"
            "    return 'a' * 64\n"
        ).encode("utf-8")
        accepted_blob = subprocess.check_output(
            ["/usr/bin/git", "hash-object", "--stdin"], input=accepted_parent
        ).decode("ascii").strip()
        child_source = CHILD_SOURCE.read_text(encoding="utf-8")
        child_source, count = PIN_RE.subn(
            f'GENERATED_PARENT_MODULE_GIT_BLOB = "{accepted_blob}"', child_source, count=1
        )
        self.assertEqual(count, 1, "fixture could not bind the child to its accepted parent blob")
        child.write_text(child_source, encoding="utf-8")
        parent.write_bytes(accepted_parent)
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
        committed_blob = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"HEAD:{PARENT_RELATIVE}"], text=True
        ).strip()
        self.assertEqual(committed_blob, accepted_blob)
        return child, parent, accepted_blob

    def _import_child(self, child: Path):
        previous = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        try:
            spec = importlib.util.spec_from_file_location("private_review_import_subject", child)
            if spec is None or spec.loader is None:
                self.fail("could not load private-review control fixture")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
        finally:
            sys.dont_write_bytecode = previous

    def test_hidden_parent_worktree_replacement_never_executes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-parent-hidden-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "attacker-parent-executed"
            child, parent, accepted_blob = self._fixture(root)
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
            self.assertNotEqual(current_blob, accepted_blob)
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
            )
            loaded = self._import_child(child)
            self.assertFalse(sentinel.exists(), "mutable hidden parent bytes executed before authority")
            self.assertEqual(loaded.generated._current_generated_subject(root), "a" * 64)

    def test_committed_descendant_parent_replacement_is_rejected_before_execution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-parent-descendant-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "attacker-descendant-executed"
            child, parent, _ = self._fixture(root)
            parent.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                "def _current_generated_subject(_root):\n"
                "    return 'b' * 64\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", PARENT_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "replace generated parent"], check=True
            )
            with self.assertRaises(Exception):
                self._import_child(child)
            self.assertFalse(sentinel.exists(), "committed replacement parent executed before pin rejection")


if __name__ == "__main__":
    unittest.main(verbosity=2)
