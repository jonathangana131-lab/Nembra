#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
XCODE = (ROOT / ".github/workflows/xcode27-pr-command.yml").read_text(encoding="utf-8")
FIELD = (ROOT / ".github/workflows/capture-field-build-provenance.yml").read_text(encoding="utf-8")


def require(source: str, token: str, label: str) -> None:
    if token not in source:
        raise SystemExit(f"{label}: missing {token!r}")


for token in (
    "actions: write",
    "current_head: ${{ steps.pr.outputs.current_head }}",
    "cancelWorkflowRun",
    "listWorkflowRuns",
    "run.id === context.runId",
    "run.head_sha !== liveHead",
    "needs.resolve.outputs.current_head == 'true'",
):
    require(XCODE, token, "xcode exact-head queue contract")

require(
    XCODE,
    "group: nembra-xcode27-pr-command-${{ needs.resolve.outputs.pr_number }}-${{ needs.resolve.outputs.head_sha }}",
    "xcode same-head dedupe contract",
)
require(XCODE, "cancel-in-progress: false", "xcode same-head dedupe contract")

for token in (
    "actions: write",
    "pull-requests: read",
    "resolve:",
    "runs-on: ubuntu-latest",
    "subject_sha: ${{ steps.subject.outputs.subject_sha }}",
    "current_head: ${{ steps.subject.outputs.current_head }}",
    "queue_scope: ${{ steps.subject.outputs.queue_scope }}",
    "cancelWorkflowRun",
    "listWorkflowRuns",
    "run.id === context.runId",
    "run.head_sha !== liveHead",
    "needs.resolve.outputs.current_head == 'true'",
    "group: nembra-capture-field-provenance-${{ needs.resolve.outputs.queue_scope }}",
    "cancel-in-progress: true",
    "ref: ${{ needs.resolve.outputs.subject_sha }}",
    "EXPECTED_HEAD_SHA: ${{ needs.resolve.outputs.subject_sha }}",
    "Reject stale PR head before scarce Mac provenance work",
):
    require(FIELD, token, "field provenance queue contract")

print("capture Mac acceptance queue discipline: PASS")
