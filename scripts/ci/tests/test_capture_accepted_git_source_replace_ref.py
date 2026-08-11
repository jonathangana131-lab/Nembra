from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


class AcceptedGitSourceReplaceRefTests(unittest.TestCase):
    def _git(self, root: Path, *arguments: str, env: dict[str, str] | None = None) -> str:
        completed = subprocess.run(
            ["git", *arguments],
            cwd=root,
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return completed.stdout.strip()

    def test_unfenced_git_show_is_demonstrably_replace_sensitive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self._git(root, "init", "-q")
            self._git(root, "config", "user.email", "capture-redteam@example.invalid")
            self._git(root, "config", "user.name", "Capture Red Team")

            helper = root / "scripts" / "helper.py"
            helper.parent.mkdir(parents=True)
            helper.write_text("accepted\n", encoding="utf-8")
            self._git(root, "add", "scripts/helper.py")
            self._git(root, "commit", "-qm", "accepted source")
            accepted = self._git(root, "rev-parse", "HEAD")

            helper.write_text("attacker\n", encoding="utf-8")
            self._git(root, "add", "scripts/helper.py")
            self._git(root, "commit", "-qm", "replacement source")
            replacement = self._git(root, "rev-parse", "HEAD")
            self._git(root, "replace", accepted, replacement)

            redirected = self._git(root, "show", f"{accepted}:scripts/helper.py")
            replacement_blind_environment = dict(os.environ)
            replacement_blind_environment["GIT_NO_REPLACE_OBJECTS"] = "1"
            authoritative = self._git(
                root,
                "show",
                f"{accepted}:scripts/helper.py",
                env=replacement_blind_environment,
            )

            self.assertEqual(redirected, "attacker")
            self.assertEqual(authoritative, "accepted")

    def test_field_accepted_git_source_loader_declares_replace_ref_fence(self) -> None:
        script = INSTALLER.read_text(encoding="utf-8")
        self.assertIn(
            "run_accepted_source_python",
            script,
            "field installer must expose the accepted-Git source runner before this red-team can turn green",
        )
        self.assertIn(
            "GIT_NO_REPLACE_OBJECTS",
            script,
            "accepted source execution must be replacement-blind; bare git show <accepted-sha>:<path> is attacker-redirectable",
        )
        self.assertIn(
            "git",
            script,
            "accepted source execution contract unexpectedly stopped using Git object authority; review the replacement-blind invariant",
        )


if __name__ == "__main__":
    unittest.main()
