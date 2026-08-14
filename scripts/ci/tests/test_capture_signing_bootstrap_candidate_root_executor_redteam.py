#!/usr/bin/env python3
"""Portable red-team for mutable PR bytes becoming the signing-bootstrap root child.

SUCCESS means the pinned parent is RED at CI custody. This test never invokes sudo/root.
"""
from __future__ import annotations

from pathlib import Path
import json


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/capture-apple-signing-trusted-bootstrap-hardening.yml"
SUBJECT = ROOT / "scripts/ci/tests/test_capture_apple_signing_trusted_bootstrap_hardening.py"
MUTABLE_SUBJECT = "scripts/ci/tests/test_capture_apple_signing_trusted_bootstrap_hardening.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> int:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    subject = SUBJECT.read_text(encoding="utf-8")

    # The workflow itself is selected from the candidate PR event and checks out the mutable PR head.
    require("pull_request:" in workflow, "parent no longer exposes this candidate PR workflow shape")
    require(
        "github.event.pull_request.head.sha" in workflow,
        "parent no longer checks out the mutable PR head for this witness",
    )

    # The exact-delta oracle explicitly permits the same file that later becomes the root child.
    require(MUTABLE_SUBJECT in workflow, "mutable privileged subject is no longer an admitted PR path")
    require(
        "/usr/bin/python3 -B -I scripts/ci/tests/test_capture_apple_signing_trusted_bootstrap_hardening.py" in workflow,
        "workflow no longer executes the candidate witness from the checked-out PR tree",
    )

    # The ordinary phase then re-enters this same __file__ under passwordless sudo/root.
    require('"/usr/bin/sudo"' in subject and '"-n"' in subject, "subject no longer spends noninteractive sudo")
    require(
        "str(Path(__file__).resolve())" in subject and '"--root-child"' in subject,
        "subject no longer promotes its own candidate-controlled bytes into the root child",
    )

    record = {
        "schema": 1,
        "validationOnly": True,
        "pinnedParent": "bf8fd13b0bab33365a306b3fb39988e2dee0f759",
        "candidateWorkflowChecksOutMutablePRHead": True,
        "candidateDeltaAllowsPrivilegedSubjectMutation": True,
        "candidateSubjectReexecutesOwnFileAsRoot": True,
        "parentCandidateControlledRootExecutor": True,
        "rootExecuted": False,
        "physicalAuthorityCreated": False,
        "productionAcceptanceClaimed": False,
    }
    print("NEMBRA_CANDIDATE_ROOT_EXECUTOR_REDTEAM_JSON=" + json.dumps(record, sort_keys=True))
    print("PARENT_RED candidateControlledRootExecutor=true rootExecuted=false physicalAuthorityCreated=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
