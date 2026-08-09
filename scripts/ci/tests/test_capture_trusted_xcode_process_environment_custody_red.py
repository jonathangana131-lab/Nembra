#!/usr/bin/env python3
"""Expected-red contract for trusted Xcode producer process-environment custody.

Pinning the trusted Simulator producer's Git blob is necessary but not sufficient when candidate
code executes earlier in the same GitHub Actions job. Repository-controlled tests/scripts can write
future-step variables through GITHUB_ENV. A later non-interactive Bash may consume BASH_ENV before
its `run:` body, and an ambient PATH can redirect the frozen producer's unqualified tool calls.

The authority-producing step must therefore either execute before any candidate-controlled host
code can mutate future-step environment, or start under a runner-selected clean shell boundary; and
the pinned producer itself must execute under a closed environment rather than inheriting ambient
candidate-influenced process state.
"""
from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
PIN_STEP = "Verify trusted Capture evidence producer blob"
BUILD_STEP = "Build, test, and capture Simulator states"


def step_source(workflow: str, name: str) -> str:
    marker = f"      - name: {name}\n"
    start = workflow.index(marker)
    next_step = workflow.find("\n      - name: ", start + len(marker))
    return workflow[start:] if next_step < 0 else workflow[start:next_step]


class TrustedXcodeProcessEnvironmentCustodyExpectedRedTests(unittest.TestCase):
    def test_bash_env_can_execute_before_a_noninteractive_step_body(self) -> None:
        """Document the shell semantic that makes inherited BASH_ENV authority-bearing."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            marker = root / "startup-ran"
            hook = root / "candidate-bash-env.sh"
            hook.write_text(f"printf owned > {marker!s}\n", encoding="utf-8")
            environment = {
                "PATH": "/usr/bin:/bin",
                "HOME": temporary,
                "BASH_ENV": str(hook),
            }
            subprocess.run(
                ["/bin/bash", "-c", "true"],
                check=True,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(marker.read_text(encoding="utf-8"), "owned")

    def test_trusted_producer_interpreter_does_not_inherit_ambient_environment(self) -> None:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        execution = step_source(workflow, BUILD_STEP)

        # The immutable Git object must not merely be piped into an ambient /bin/bash. The command
        # segment that launches the authority-producing Bash itself must contain env -i plus a closed
        # system PATH. An env -i used only for the *left-hand* git cat-file process is not sufficient.
        bash_index = execution.find("/bin/bash")
        self.assertGreaterEqual(bash_index, 0, "trusted workflow no longer invokes Bash for the pinned producer")
        pipe_index = execution.rfind("|", 0, bash_index)
        self.assertGreaterEqual(pipe_index, 0, "trusted workflow no longer streams the pinned producer into Bash")
        bash_launch_segment = execution[pipe_index:bash_index]
        self.assertIn(
            "env -i",
            bash_launch_segment,
            "trusted producer Bash must itself be launched behind a closed env -i boundary",
        )
        self.assertIn(
            "PATH=/usr/bin:/bin",
            bash_launch_segment,
            "trusted producer Bash clean environment must carry an explicit system PATH",
        )

    def test_candidate_host_code_cannot_poison_authority_step_startup(self) -> None:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        pin_index = workflow.index(f"      - name: {PIN_STEP}")
        build_index = workflow.index(f"      - name: {BUILD_STEP}")
        self.assertLess(pin_index, build_index)

        intervening = workflow[pin_index:build_index]
        candidate_host_steps = (
            "Validate project structure",
            "Validate core package",
            "Validate Capture package",
            "Validate signed field evidence tooling",
            "Validate signed field candidate producer source",
            "Validate offline field authorization signer",
        )
        has_candidate_host_code_before_authority = any(
            f"- name: {name}" in intervening for name in candidate_host_steps
        )

        execution = step_source(workflow, BUILD_STEP)
        header = execution.split("        run: |", 1)[0]
        starts_with_clean_runner_shell = "shell:" in header and "env -i" in header

        self.assertTrue(
            starts_with_clean_runner_shell or not has_candidate_host_code_before_authority,
            "candidate-controlled host code runs before the trusted authority step, but the step "
            "does not start under a clean runner-selected shell; GITHUB_ENV can influence Bash "
            "startup/tool resolution before the run body can defend itself",
        )


if __name__ == "__main__":
    unittest.main()
