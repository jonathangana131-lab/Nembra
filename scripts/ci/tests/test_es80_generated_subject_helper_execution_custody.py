#!/usr/bin/env python3
"""Production regression for R3 generated-subject helper execution custody."""

from __future__ import annotations

import importlib.util
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
    def test_swap_restore_worktree_helper_cannot_change_executed_semantics(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-generated-helper-exec-") as temporary:
            root = Path(temporary).resolve(strict=True)
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

            accepted_digest = "a" * 64
            attacker_digest = "b" * 64
            helper = repository / GO.GENERATED_HELPER_PATH
            helper.parent.mkdir(parents=True, exist_ok=True)
            accepted_helper_bytes = (
                "#!/usr/bin/env python3\n"
                f"# {GO.GENERATED_SCHEMA}\n"
                f"print({accepted_digest!r})\n"
            )
            substituted_helper_bytes = (
                "#!/usr/bin/env python3\n"
                "# attacker-controlled replacement; intentionally ignores build inputs\n"
                f"print({attacker_digest!r})\n"
            )
            helper.write_text(accepted_helper_bytes, encoding="utf-8")

            fixtures = {
                "Scripts/bootstrap_capture_tuya_sdk.sh": (
                    f"# {GO.GENERATED_ENV}\n"
                    "# capture_cocoapods_generated_build_subject.py\n"
                ),
                "Scripts/capture_tuya_private_input_provenance.py": "# private provenance helper\n",
                "Scripts/capture_tuya_private_input_build_guard.py": (
                    "# capture_cocoapods_generated_build_subject.py\n"
                    "# _verify_accepted_generated_build_subject\n"
                    "# require_accepted_generated_subject=True\n"
                    "# _require_real_checkout_ancestry\n"
                    "# _ensure_fd_budget\n"
                    "# KQ_NOTE_ATTRIB\n"
                ),
                "scripts/field/install_one_time_capture.command": (
                    "# bootstrap_capture_tuya_sdk.sh\n"
                    "# capture_tuya_private_input_build_guard.py\n"
                ),
                ".github/workflows/capture-cocoapods-build-subject-redteam.yml": (
                    "name: Capture CocoaPods Build Subject Authority\n"
                    "# Require exact generated CocoaPods build authority\n"
                    "# test_capture_private_input_ancestor_retarget.py\n"
                ),
                ".github/workflows/capture-cocoapods-vnode-attribute-convergence.yml": (
                    "name: Capture CocoaPods Vnode Attribute Convergence\n"
                    "# Real macOS chmod vnode evidence\n"
                    "# macos-15\n"
                ),
            }
            for relative, text in fixtures.items():
                path = repository / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")

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

            base = GO._load_base_module()
            real_run = subprocess.run
            swapped = False
            attacker_output_seen = False

            def swap_at_python_stdin_exec(args, *positional, **keyword):
                nonlocal swapped, attacker_output_seen
                argv = list(args) if isinstance(args, (list, tuple)) else []
                if (
                    len(argv) >= 4
                    and argv[0] == "/usr/bin/python3"
                    and argv[1:4] == ["-I", "-B", "-"]
                ):
                    swapped = True
                    helper.write_text(substituted_helper_bytes, encoding="utf-8")
                    try:
                        result = real_run(args, *positional, **keyword)
                        stdout = result.stdout
                        if isinstance(stdout, bytes):
                            stdout = stdout.decode("utf-8", errors="replace")
                        attacker_output_seen = str(stdout).strip() == attacker_digest
                        return result
                    finally:
                        helper.write_text(accepted_helper_bytes, encoding="utf-8")
                return real_run(args, *positional, **keyword)

            with mock.patch.object(GO.subprocess, "run", side_effect=swap_at_python_stdin_exec):
                record = GO.candidate_generated_authority(
                    repository,
                    source,
                    accepted_digest,
                    base=base,
                )

            self.assertTrue(swapped, "regression never reached the pinned Python execution boundary")
            self.assertFalse(attacker_output_seen, "replacement worktree helper controlled the derived digest")
            self.assertEqual(record[GO.GENERATED_KEY], accepted_digest)
            self.assertEqual(helper.read_text(encoding="utf-8"), accepted_helper_bytes)
            self.assertEqual(
                subprocess.check_output(
                    ["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"],
                    text=True,
                ),
                "",
                "swap/restore should leave the candidate apparently clean after the authority call",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
