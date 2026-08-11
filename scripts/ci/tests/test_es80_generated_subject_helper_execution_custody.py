#!/usr/bin/env python3
"""Regression: Final-GO executes accepted helper Git bytes, never mutable worktree helper bytes."""
from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO R3 child")
GO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GO)


class GeneratedSubjectHelperExecutionCustodyTests(unittest.TestCase):
    def _fixture(self, root: Path, output: str):
        repository = root / "candidate"
        repository.mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"], check=True)
        helper = repository / GO.GENERATED_HELPER_PATH
        helper.parent.mkdir(parents=True, exist_ok=True)
        helper.write_text(
            "#!/usr/bin/env python3\n"
            "from pathlib import Path\n"
            f"SCHEMA = {GO.GENERATED_SCHEMA.encode()!r}\n"
            "class GeneratedBuildSubjectError(RuntimeError):\n    pass\n"
            "def build_subject(*, lockfile: Path, pods: Path, workspace: Path) -> str:\n"
            "    assert lockfile.name == 'Podfile.lock'\n"
            "    assert pods.name == 'Pods'\n"
            "    assert workspace.name == 'NembraCapture.xcworkspace'\n"
            f"    return {output!r}\n",
            encoding="utf-8",
        )
        (repository / "Podfile.lock").write_text("PODS:\n", encoding="utf-8")
        (repository / "Pods").mkdir()
        (repository / "NembraCapture.xcworkspace").mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(repository), "add", "."], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(repository), "commit", "-qm", "accepted fixture"], check=True)
        source = subprocess.check_output(["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
        return repository, source, GO._load_base_module()

    def test_exact_accepted_helper_git_blob_executes_in_memory(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-git-green-") as temporary:
            expected = "b" * 64
            repository, source, base = self._fixture(Path(temporary), expected)
            self.assertEqual(GO._current_generated_subject(repository, source, base), expected)
            self.assertEqual(subprocess.check_output(["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"], text=True), "")

    def test_mutable_worktree_helper_substitution_cannot_control_execution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-git-swap-") as temporary:
            accepted_output = "b" * 64
            attacker_output = "a" * 64
            repository, source, base = self._fixture(Path(temporary), accepted_output)
            helper = repository / GO.GENERATED_HELPER_PATH
            accepted_bytes = helper.read_bytes()
            helper.write_text(
                "#!/usr/bin/env python3\n"
                f"SCHEMA = {GO.GENERATED_SCHEMA.encode()!r}\n"
                "def build_subject(**kwargs):\n"
                f"    return {attacker_output!r}\n",
                encoding="utf-8",
            )
            self.assertNotEqual(helper.read_bytes(), accepted_bytes)
            self.assertEqual(
                GO._current_generated_subject(repository, source, base),
                accepted_output,
                "mutable worktree helper bytes influenced accepted Git execution subject",
            )
            helper.write_bytes(accepted_bytes)
            self.assertEqual(subprocess.check_output(["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"], text=True), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
