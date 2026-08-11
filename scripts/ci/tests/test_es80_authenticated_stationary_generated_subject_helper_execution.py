#!/usr/bin/env python3
"""Exact-current regressions for R3 generated-subject helper execution custody."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go_helper_execution", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO module")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

DIGEST = "ab" * 32
ATTACKER_DIGEST = "cd" * 32


def git(root: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    process = subprocess.run(
        ["/usr/bin/git", "-C", str(root), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.returncode != 0:
        raise AssertionError(process.stderr.decode("utf-8", errors="replace"))
    return process.stdout


class GeneratedSubjectHelperExecutionTests(unittest.TestCase):
    def accepted_repo(self, root: Path) -> tuple[str, Path, bytes]:
        git(root, "init", "-q")
        git(root, "config", "user.email", "nembra-test@example.invalid")
        git(root, "config", "user.name", "Nembra Test")
        helper = root / MODULE.GENERATED_HELPER_PATH
        helper.parent.mkdir(parents=True)
        accepted = (
            "#!/usr/bin/env python3\n"
            "# nembra-capture-cocoapods-generated-build-subject-v1\n"
            f"print('{DIGEST}')\n"
        ).encode()
        helper.write_bytes(accepted)
        git(root, "add", MODULE.GENERATED_HELPER_PATH)
        git(root, "commit", "-qm", "accepted generated helper")
        source = git(root, "rev-parse", "HEAD").decode("ascii").strip()
        return source, helper, accepted

    def test_post_review_worktree_replacement_cannot_change_executed_helper(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-exec-") as temporary:
            root = Path(temporary)
            source, helper, accepted = self.accepted_repo(root)
            helper.write_text(
                "#!/usr/bin/env python3\n"
                f"print('{ATTACKER_DIGEST}')\n",
                encoding="utf-8",
            )

            # The attacker pathname is now different, but the authority side effect
            # executes SOURCE_SHA:helper bytes rather than reopening that pathname.
            self.assertEqual(MODULE._current_generated_subject(root, source), DIGEST)
            self.assertEqual(MODULE._accepted_generated_helper(root, source), accepted)

    def test_git_replace_object_cannot_redirect_accepted_helper_blob(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-replace-") as temporary:
            root = Path(temporary)
            source, _helper, accepted = self.accepted_repo(root)
            accepted_blob = git(
                root, "rev-parse", f"{source}:{MODULE.GENERATED_HELPER_PATH}"
            ).decode("ascii").strip()
            attacker_blob = git(
                root,
                "hash-object",
                "-w",
                "--stdin",
                input_bytes=b"print('redirected attacker helper')\n",
            ).decode("ascii").strip()
            replace = root / ".git" / "refs" / "replace" / accepted_blob
            replace.parent.mkdir(parents=True, exist_ok=True)
            replace.write_text(attacker_blob + "\n", encoding="ascii")

            self.assertEqual(MODULE._accepted_generated_helper(root, source), accepted)
            self.assertEqual(MODULE._current_generated_subject(root, source), DIGEST)

    def test_source_commit_not_dynamic_head_owns_execution_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-source-") as temporary:
            root = Path(temporary)
            source, helper, _accepted = self.accepted_repo(root)
            helper.write_text(
                "#!/usr/bin/env python3\n"
                f"print('{ATTACKER_DIGEST}')\n",
                encoding="utf-8",
            )
            git(root, "add", MODULE.GENERATED_HELPER_PATH)
            git(root, "commit", "-qm", "later helper")
            self.assertNotEqual(git(root, "rev-parse", "HEAD").decode().strip(), source)
            self.assertEqual(MODULE._current_generated_subject(root, source), DIGEST)


if __name__ == "__main__":
    unittest.main(verbosity=2)
