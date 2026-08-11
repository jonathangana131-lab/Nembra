#!/usr/bin/env python3
"""Expected-red Final-GO diagnostic for generated-subject helper execution custody.

The generated-subject control child first proves the helper's current worktree bytes equal the
accepted Git blob, then later launches that helper again by mutable pathname. The accepted parent
already treats this swap/restore class as authority-significant for the installer itself. This test
requires the independent generated-subject re-derivation to fail closed if different helper bytes
are consumed at that execution boundary, even when the accepted pathname is restored immediately.
"""

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
    raise RuntimeError("could not load generated-subject Final-GO child")
GO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GO)


class GeneratedSubjectHelperExecutionCustodyTests(unittest.TestCase):
    def test_swap_restore_helper_at_execution_boundary_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-generated-helper-exec-") as temporary:
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
            reviewed_helper_output = "b" * 64
            helper = repository / "Scripts/capture_cocoapods_build_subject.py"
            helper.parent.mkdir(parents=True, exist_ok=True)
            accepted_helper_bytes = (
                "#!/usr/bin/env python3\n"
                "# nembra-cocoapods-generated-build-subject-v1\n"
                f"print({reviewed_helper_output!r})\n"
            )
            substituted_helper_bytes = (
                "#!/usr/bin/env python3\n"
                "# attacker-controlled replacement: does not inspect lock/Pods/workspace\n"
                f"print({accepted_digest!r})\n"
            )
            helper.write_text(accepted_helper_bytes, encoding="utf-8")

            fixtures = {
                "Scripts/bootstrap_capture_tuya_sdk.sh": (
                    "# NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256\n"
                    "# capture_cocoapods_build_subject.py\n"
                ),
                "Scripts/capture_tuya_private_input_provenance.py": "# private provenance helper\n",
                "Scripts/capture_tuya_private_input_build_guard.py": (
                    "# accepted_generated_subject_sha256\n"
                    "# require_accepted_generated_subject\n"
                ),
                "scripts/field/install_one_time_capture.command": (
                    "# bootstrap_capture_tuya_sdk.sh\n"
                    "# capture_tuya_private_input_build_guard.py\n"
                ),
            }
            for relative, text in fixtures.items():
                path = repository / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")

            # The malicious replacement deliberately ignores these inputs. They exist only to make
            # the candidate shape realistic enough for the real helper invocation arguments.
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
            replacement_was_consumed = False

            def swap_at_helper_exec(args, *positional, **keyword):
                nonlocal swapped, replacement_was_consumed
                argv = list(args) if isinstance(args, (list, tuple)) else []
                if (
                    len(argv) >= 4
                    and argv[0] == "/usr/bin/python3"
                    and argv[1:3] == ["-I", "-B"]
                    and argv[3] == str(helper)
                ):
                    swapped = True
                    helper.write_text(substituted_helper_bytes, encoding="utf-8")
                    try:
                        result = real_run(args, *positional, **keyword)
                        replacement_was_consumed = result.stdout.strip() == accepted_digest
                        return result
                    finally:
                        helper.write_text(accepted_helper_bytes, encoding="utf-8")
                return real_run(args, *positional, **keyword)

            # Production requirement: the accepted helper execution subject itself must be pinned.
            # Merely checking its bytes earlier and restoring them afterward must not earn authority.
            with mock.patch.object(GO.subprocess, "run", side_effect=swap_at_helper_exec):
                with self.assertRaises(
                    GO.GeneratedSubjectGoError,
                    msg=(
                        "Final GO accepted a generated-subject digest emitted by helper bytes that "
                        "differed from the exact Git blob previously reviewed"
                    ),
                ):
                    GO.candidate_generated_authority(
                        repository,
                        source,
                        accepted_digest,
                        base=base,
                    )

            self.assertTrue(swapped, "diagnostic never reached the real helper execution boundary")
            self.assertTrue(
                replacement_was_consumed,
                "diagnostic did not prove the substituted helper bytes controlled the derived digest",
            )
            self.assertEqual(
                helper.read_text(encoding="utf-8"),
                accepted_helper_bytes,
                "diagnostic must restore the accepted pathname to model a swap/restore attack",
            )
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
