#!/usr/bin/env python3
"""Regression coverage for trusted Xcode authority-step process startup custody."""
from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = ROOT / ".github/workflows/capture-xcode27-trusted-command.yml"
BUILD_STEP = "Build, test, and capture Simulator states"
VERIFY_STEP = "Verify retained Capture evidence against trusted resolver authority"
CANDIDATE_STEPS = (
    "Validate project structure",
    "Validate core package",
    "Validate Capture package",
    "Validate signed field evidence tooling",
    "Validate signed field candidate producer source",
    "Validate offline field authorization signer",
)


def step_source(workflow: str, name: str) -> str:
    marker = f"      - name: {name}\n"
    start = workflow.index(marker)
    next_step = workflow.find("\n      - name: ", start + len(marker))
    return workflow[start:] if next_step < 0 else workflow[start:next_step]


def step_header(workflow: str, name: str) -> str:
    source = step_source(workflow, name)
    return source.split("        run: |", 1)[0]


class TrustedXcodeStepStartupCustodyTests(unittest.TestCase):
    def test_bash_env_executes_before_an_ordinary_noninteractive_bash_body(self) -> None:
        """Keep the shell semantic behind this authority invariant executable in CI."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            marker = root / "startup-ran"
            hook = root / "candidate-bash-env.sh"
            hook.write_text(f"printf owned > {marker!s}\n", encoding="utf-8")
            subprocess.run(
                ["/bin/bash", "-c", "true"],
                check=True,
                env={"PATH": "/usr/bin:/bin", "HOME": temporary, "BASH_ENV": str(hook)},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(marker.read_text(encoding="utf-8"), "owned")

    def test_authority_and_retained_verifier_start_under_runner_selected_clean_shell(self) -> None:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        for name in (BUILD_STEP, VERIFY_STEP):
            with self.subTest(step=name):
                header = step_header(workflow, name)
                self.assertIn("shell:", header)
                self.assertIn("/usr/bin/env -i", header)
                self.assertIn("PATH=/usr/bin:/bin:/usr/sbin:/sbin", header)
                self.assertIn("/bin/bash --noprofile --norc", header)

    def test_candidate_host_code_runs_before_authority_but_cannot_supply_bash_startup_state(self) -> None:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        build_index = workflow.index(f"      - name: {BUILD_STEP}")
        self.assertTrue(
            any(workflow.index(f"      - name: {name}") < build_index for name in CANDIDATE_STEPS),
            "fixture drift: expected candidate-controlled host validation before authority step",
        )
        header = step_header(workflow, BUILD_STEP)
        self.assertIn("shell: /usr/bin/env -i", header)

    def test_clean_authority_body_does_not_depend_on_future_step_github_environment(self) -> None:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        build = step_source(workflow, BUILD_STEP)
        retained = step_source(workflow, VERIFY_STEP)
        self.assertNotIn("$GITHUB_WORKSPACE", build)
        self.assertIn("$(/bin/pwd -P)/$producer_path", build)
        self.assertNotIn("os.environ.get(\"EXPECTED_HEAD_SHA\"", retained)
        self.assertIn('expected_head = "${{ needs.resolve.outputs.head_sha }}"', retained)


if __name__ == "__main__":
    unittest.main()
