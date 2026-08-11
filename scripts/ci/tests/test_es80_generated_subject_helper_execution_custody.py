#!/usr/bin/env python3
"""Regression for exact generated-subject helper execution custody."""
from __future__ import annotations

import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load generated-subject Final-GO R3 child")
GO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GO)


class GeneratedSubjectHelperExecutionCustodyTests(unittest.TestCase):
    def _fixture(self, root: Path, output: str) -> tuple[Path, str, object]:
        repository = root / "candidate"
        repository.mkdir()
        subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)
        subprocess.run(
            ["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"],
            check=True,
        )
        subprocess.run(
            ["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"],
            check=True,
        )
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
        subprocess.run(
            ["/usr/bin/git", "-C", str(repository), "commit", "-qm", "accepted fixture"],
            check=True,
        )
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"],
            text=True,
        ).strip()
        return repository, source, GO._load_base_module()

    def test_exact_accepted_helper_blob_executes_from_in_memory_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-exec-green-") as temporary:
            expected = "b" * 64
            repository, source, base = self._fixture(Path(temporary), expected)
            self.assertEqual(
                GO._current_generated_subject(repository, source, base),
                expected,
            )
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
            )

    def test_swap_restore_helper_at_descriptor_boundary_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-exec-swap-") as temporary:
            accepted_output = "b" * 64
            attacker_output = "a" * 64
            repository, source, base = self._fixture(Path(temporary), accepted_output)
            helper = repository / GO.GENERATED_HELPER_PATH
            accepted_bytes = helper.read_bytes()
            attacker_bytes = (
                "#!/usr/bin/env python3\n"
                f"SCHEMA = {GO.GENERATED_SCHEMA.encode()!r}\n"
                "def build_subject(**kwargs):\n"
                f"    return {attacker_output!r}\n"
            ).encode()
            real_open = os.open
            swapped = False

            def swap_before_open(path, flags, *args, **kwargs):
                nonlocal swapped
                candidate = Path(path)
                if not swapped and candidate == helper:
                    swapped = True
                    attacker = helper.with_name(".attacker-helper")
                    attacker.write_bytes(attacker_bytes)
                    os.replace(attacker, helper)
                    descriptor = real_open(path, flags, *args, **kwargs)
                    restored = helper.with_name(".accepted-helper")
                    restored.write_bytes(accepted_bytes)
                    os.replace(restored, helper)
                    return descriptor
                return real_open(path, flags, *args, **kwargs)

            with mock.patch.object(GO.os, "open", side_effect=swap_before_open):
                with self.assertRaises(
                    GO.GeneratedSubjectGoError,
                    msg="substituted helper inode crossed exact accepted execution custody",
                ):
                    GO._current_generated_subject(repository, source, base)

            self.assertTrue(swapped, "regression never reached the helper descriptor boundary")
            self.assertEqual(helper.read_bytes(), accepted_bytes)
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
                "swap/restore should leave the checkout apparently clean",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
